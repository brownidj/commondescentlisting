#!/usr/bin/env python3
"""Retrieve Common Descent RSS episode metadata using Python's standard library.

Newly written script, not a script supplied by the DeepSeek conversation.
Usage: python3 retrieve-episodes.py [--output episodes.csv] [--feed URL]
Writes the original RSS beside the CSV for reproducibility.
"""
import argparse
import csv
from email.utils import parsedate_to_datetime
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET

ITUNES = '{http://www.itunes.com/dtds/podcast-1.0.dtd}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--feed', default='https://commondescentpodcast.podbean.com/feed')
    parser.add_argument('--output', type=Path, default=Path('episodes.csv'))
    args = parser.parse_args()
    request = urllib.request.Request(args.feed, headers={'User-Agent': 'CommonDescentMetadataExport/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        resolved_url = response.url
    root = ET.fromstring(raw)
    items = root.findall('./channel/item')
    if not items:
        raise SystemExit('No RSS items found; no CSV written.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix('.rss.xml').write_bytes(raw)
    fields = ['episode_number', 'title', 'published', 'published_raw', 'episode_type',
              'duration', 'page_url', 'audio_url', 'guid']
    with args.output.open('w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in items:
            published_raw = item.findtext('pubDate', '')
            try:
                published = parsedate_to_datetime(published_raw).isoformat()
            except (TypeError, ValueError, OverflowError):
                published = ''
            enclosure = item.find('enclosure')
            writer.writerow({
                'episode_number': item.findtext(ITUNES + 'episode', ''),
                'title': item.findtext('title', ''),
                'published': published,
                'published_raw': published_raw,
                'episode_type': item.findtext(ITUNES + 'episodeType', ''),
                'duration': item.findtext(ITUNES + 'duration', ''),
                'page_url': item.findtext('link', ''),
                'audio_url': enclosure.get('url', '') if enclosure is not None else '',
                'guid': item.findtext('guid', ''),
            })
    print(f'Exported {len(items)} feed items to {args.output}')
    print(f'Feed: {resolved_url}')
    print('Includes every item exposed by this feed, which may limit its archive.')


if __name__ == '__main__':
    main()
