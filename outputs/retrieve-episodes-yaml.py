#!/usr/bin/env python3
"""Export RSS metadata and explicit news summaries/timestamps as YAML.

New script, not supplied by DeepSeek. Uses only Python's standard library.
Usage: python3 retrieve-episodes-yaml.py --output episodes.yaml
Offline: python3 retrieve-episodes-yaml.py --input episodes.rss.xml --output episodes.yaml
All feed items are included. Absent fields remain null; news summaries are
preserved as published rather than guessed into separate headlines.
"""
import argparse
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

FEED = 'https://commondescentpodcast.podbean.com/feed'
ITUNES = '{http://www.itunes.com/dtds/podcast-1.0.dtd}'


class Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in ('p', 'div', 'br', 'li'):
            self.parts.append('\n')

    def handle_endtag(self, tag):
        if tag in ('p', 'div', 'li'):
            self.parts.append('\n')


def text(html):
    parser = Text()
    parser.feed(html)
    return '\n'.join(line.strip() for line in ''.join(parser.parts).splitlines() if line.strip())


def scalar(value):
    # JSON-quoted scalar strings are valid YAML strings.
    return 'null' if value is None else json.dumps(value, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--feed', default=FEED)
    parser.add_argument('--input', type=Path)
    parser.add_argument('--output', type=Path, default=Path('episodes.yaml'))
    args = parser.parse_args()
    if args.input:
        raw = args.input.read_bytes()
    else:
        request = urllib.request.Request(args.feed, headers={'User-Agent': 'CommonDescentMetadataExport/1.0'})
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
    root = ET.fromstring(raw)
    items = root.findall('./channel/item')
    if not items:
        raise SystemExit('No RSS items found; no YAML written.')
    lines = ['podcast:', '  title: ' + scalar(root.findtext('./channel/title')),
             '  rss: ' + scalar(args.feed),
             '  listing_granularity: "one episode per entry; news is a segment field"',
             'episodes:']
    summary_count = timestamp_count = 0
    for item in items:
        title = item.findtext('title', '')
        numbered = re.match(r'^Episode\s+(\d+(?:\.\d+)?[A-Za-z]?)\s*[-–:]\s*(.*)$', title, re.I)
        episode_number = numbered.group(1) if numbered else None
        description = text(item.findtext('description', ''))
        summary = re.search(r'(?im)^In the news\s*:\s*([^\n]+)', description)
        timestamp = re.search(r'(?im)^\s*News\s*:\s*(\d{1,2}:\d{2}(?::\d{2})?)\b', description)
        summary_count += bool(summary)
        timestamp_count += bool(timestamp)
        published_raw = item.findtext('pubDate', '')
        try:
            date = parsedate_to_datetime(published_raw).date().isoformat()
        except (TypeError, ValueError, OverflowError):
            date = None
        enclosure = item.find('enclosure')
        fields = {
            'episode_number': episode_number,
            'rss_episode_number': item.findtext(ITUNES + 'episode'),
            'title': numbered.group(2) if numbered else title,
            'original_title': title,
            'date': date,
            'published_raw': published_raw,
            'type': 'Main' if numbered else None,
            'rss_episode_type': item.findtext(ITUNES + 'episodeType'),
            'page_url': item.findtext('link'),
            'audio_url': enclosure.get('url') if enclosure is not None else None,
            'guid': item.findtext('guid'),
            'description': description,
        }
        for index, (key, value) in enumerate(fields.items()):
            lines.append(('  - ' if index == 0 else '    ') + key + ': ' + scalar(value))
        lines.extend(['    news:',
                      '      start_time: ' + scalar(timestamp.group(1) if timestamp else None),
                      '      summary: ' + scalar(summary.group(1).strip() if summary else None),
                      '      headlines: null'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    args.output.with_suffix('.rss.xml').write_bytes(raw)
    print(f'Exported {len(items)} items; {summary_count} news summaries; {timestamp_count} news timestamps.')
    print(f'Output: {args.output}')


if __name__ == '__main__':
    main()
