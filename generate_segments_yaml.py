"""Export Option 2 YAML: one record per news item or discussion segment.

News headline boundaries are inferred from commas/semicolons and require review.
Individual news item timestamps are unknown; news_start_time is the shared
news section timestamp. Only explicitly published discussion times are used.
Uses Python's standard library; no additional packages are required.
"""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

FEED = 'https://commondescentpodcast.podbean.com/feed'


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


def split_news(summary):
    """Heuristic boundaries; preserve the full source text in every record."""
    parts = re.split(r'[;,]\s*', summary)
    return [cleaned for part in parts
            if (cleaned := re.sub(r'^(?:and|also)\s+', '', part.strip(), flags=re.I).strip(' .'))]


def extract_segments(item):
    title = item.findtext('title', '')
    numbered = re.match(r'^Episode\s+(\d+(?:\.\d+)?[A-Za-z]?)\s*[-–—:]\s*(.*)$', title, re.I)
    description = text(item.findtext('description', ''))
    common = {
        'episode_number': numbered.group(1) if numbered else None,
        'episode_title': numbered.group(2) if numbered else title,
        'source_url': item.findtext('link'),
        'guid': item.findtext('guid'),
    }
    summary = re.search(r'(?im)^In the news\s*:\s*([^\n]+)', description)
    news_time = re.search(r'(?im)^News\s*:\s*(\d{1,2}:\d{2}(?::\d{2})?)\b', description)
    segments = []
    if summary:
        for headline in split_news(summary.group(1)):
            segments.append({**common, 'segment_type': 'News',
                             'segment_title': headline, 'start_time': None,
                             'news_start_time': news_time.group(1) if news_time else None,
                             'news_raw': summary.group(1).strip(),
                             'headline_split_method': 'comma/semicolon heuristic',
                             'needs_review': True})
    # Keep an explicit news section even if the feed has no headline summary.
    elif news_time:
        segments.append({**common, 'segment_type': 'News',
                         'segment_title': None, 'start_time': news_time.group(1),
                         'news_raw': None, 'needs_review': True})
    discussions = re.findall(
        r'(?im)^(Main discussion[^:\n]*):\s*(\d{1,2}:\d{2}(?::\d{2})?)\b', description)
    if numbered:
        if discussions:
            for label, timestamp in discussions:
                segments.append({**common, 'segment_type': 'Main Discussion',
                                 'segment_title': common['episode_title'],
                                 'segment_label': label, 'start_time': timestamp})
        else:
            segments.append({**common, 'segment_type': 'Main Discussion',
                             'segment_title': common['episode_title'], 'start_time': None})
    else:
        # Preserve unnumbered side episodes without asserting a discussion type.
        segments.append({**common, 'segment_type': 'Episode',
                         'segment_title': title, 'start_time': None})
    return segments


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--feed', default=FEED)
    parser.add_argument('--input', type=Path, help='Use a saved RSS XML file offline')
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parent / 'data' / 'segments.yaml')
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
        raise SystemExit('No RSS items found; no files written.')
    segments = [segment for item in items for segment in extract_segments(item)]
    lines = ['podcast:', '  title: ' + scalar(root.findtext('./channel/title')),
             '  rss: ' + scalar(args.feed),
             '  listing_granularity: "one segment per entry"', 'segments:']
    for segment in segments:
        for index, (key, value) in enumerate(segment.items()):
            lines.append(('  - ' if index == 0 else '    ') + key + ': ' + scalar(value))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    args.output.with_suffix('.rss.xml').write_bytes(raw)
    news_count = sum(segment['segment_type'] == 'News' for segment in segments)
    print(f'Exported {len(segments)} segments from {len(items)} feed items ({news_count} News records).')
    print(f'Output: {args.output}')
    print('Automatically split news headlines are marked needs_review: true.')


if __name__ == '__main__':
    main()
