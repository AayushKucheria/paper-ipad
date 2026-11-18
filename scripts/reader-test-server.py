#!/usr/bin/env python3
"""Local Reader API fixture for the real simulator flow. No real credentials/data."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import json, time, threading, io, zipfile

PORT = 18767
BASE = f'http://localhost:{PORT}'
metrics = {'catalog_requests': 0, 'pdf_requests': 0, 'pdf_authorization_headers': 0, 'analysis_requests': 0, 'highlight_posts': 0, 'incremental_requests': 0, 'article_requests': 0, 'epub_list_requests': 0, 'epub_file_requests': 0}
highlights = []
lock = threading.Lock()

def pdf_bytes():
    stream = b'BT /F1 24 Tf 60 700 Td (A field guide to slow reading) Tj ET'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>', b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream']
    out = b'%PDF-1.4\n'; offsets = [0]
    for number, obj in enumerate(objects, 1):
        offsets.append(len(out)); out += f'{number} 0 obj\n'.encode()+obj+b'\nendobj\n'
    xref = len(out)
    out += f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()
    out += b''.join(f'{offset:010} 00000 n \n'.encode() for offset in offsets[1:])
    return out + f'trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()

def epub_bytes():
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w') as z:
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip')
        z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        z.writestr('OPS/book.opf', '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">fixture-book</dc:identifier><dc:title>The fixture book</dc:title><dc:creator>Paper test library</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>')
        z.writestr('OPS/text/a.xhtml', '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter one</title></head><body><h1>Chapter one</h1><p>Epub fixture sentence for reading.</p></body></html>')
    return out.getvalue()

def epub_document(identifier, title, raw=True, source_url=''):
    # Shapes seen on real uploaded EPUBs: empty source_url/author/image_url, null title for unreadable uploads.
    return {'id': identifier, 'title': title, 'author': 'Paper test library' if title else '', 'summary': 'A book for handwritten notes.' if title else 'Your file was uploaded but we were unable to load and read it.',
        'category': 'epub', 'parent_id': None, 'url': f'https://read.readwise.io/read/{identifier}', 'source_url': source_url,
        'image_url': '', 'saved_at': '2026-10-21T00:00:00Z', 'reading_progress': 0,
        'raw_source_url': f'{BASE}/files/{identifier}.epub' if raw else ''}

def document(identifier, title, author=None, summary=None, available=True):
    return {'id': identifier, 'title': title, 'author': author, 'summary': summary,
        'category': 'pdf', 'parent_id': None, 'url': f'https://read.readwise.io/read/{identifier}',
        'source_url': None, 'saved_at': '2026-10-20T12:00:00Z',
        'raw_source_url': f'{BASE}/files/{identifier}.pdf' if available else None}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def reply(self, status, value, content_type='application/json'):
        data = value if isinstance(value, bytes) else json.dumps(value).encode()
        self.send_response(status); self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        parsed = urlparse(self.path); query = parse_qs(parsed.query)
        if parsed.path == '/metrics': return self.reply(200, metrics)
        if parsed.path == '/reset':
            highlights.clear()
            with lock:
                for key in metrics: metrics[key] = 0
            return self.reply(200, metrics)
        if parsed.path.startswith('/files/') and parsed.path.endswith('.epub'):
            with lock: metrics['epub_file_requests'] += 1
            return self.reply(200, epub_bytes(), 'application/epub+zip')
        if parsed.path.startswith('/files/'):
            with lock:
                metrics['pdf_requests'] += 1
                metrics['pdf_authorization_headers'] += bool(self.headers.get('Authorization'))
            time.sleep(2)
            return self.reply(200, pdf_bytes(), 'application/pdf')
        if parsed.path == '/api/v3/list/':
            if self.headers.get('Authorization') != 'Token ui-test-token': return self.reply(401, {})
            with lock: metrics['catalog_requests'] += 1
            if query.get('category') == ['highlight']:
                return self.reply(200, {'results':highlights, 'nextPageCursor':None})
            if query.get('category') == ['epub'] or query.get('id') == ['book']:
                with lock: metrics['epub_list_requests'] += 1
                return self.reply(200, {'count':2, 'results':[epub_document('broken', None, raw=False), epub_document('book', 'The fixture book', source_url='private://read/book')], 'nextPageCursor':None})
            if query.get('category') == ['article'] or (query.get('id') == ['article']):
                with lock: metrics['article_requests'] += 1
                article = {'id':'article', 'title':'Thinking with a pencil', 'author':'Paper test library', 'summary':'An article for handwritten ideas.', 'category':'article', 'parent_id':None, 'url':'https://read.readwise.io/read/article', 'source_url':'https://example.com/thinking', 'saved_at':'2026-10-22T00:00:00Z', 'html_content':'<article><h1>Thinking with a pencil</h1><p>Writing helps us see what we think.</p><p>Leave room for questions and diagrams.</p></article>'}
                article['html_content'] = article['html_content'].replace(
                    '</article>',
                    ''.join(f'<p>Fixture paragraph {index}. Keep reading for another writing exercise.</p>'
                            for index in range(1, 31)) + '</article>')
                return self.reply(200, {'results':[article], 'nextPageCursor':None})
            if query.get('updatedAfter'):
                with lock: metrics['incremental_requests'] += 1
                return self.reply(200, {'results':[], 'nextPageCursor':None})
            if query.get('id'):
                return self.reply(200, {'results':[document('guide', 'A field guide to slow reading', 'Paper test library', 'Margins, notes, and meaning.')], 'nextPageCursor':None})
            if query.get('pageCursor'):
                return self.reply(200, {'results':[document('second', 'Thinking on paper', None, None)], 'nextPageCursor':None})
            return self.reply(200, {'results':[document('guide', 'A field guide to slow reading', 'Paper test library', 'Margins, notes, and meaning.'), document('unavailable', 'An unavailable original', available=False)], 'nextPageCursor':'page-two'})
        return self.reply(404, {})

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        payload = json.loads(self.rfile.read(length))
        if self.path == '/api/anthropic/messages' or self.path == '/anthropic/messages':
            if self.headers.get('x-api-key') != 'fake-anthropic-key': return self.reply(401, {})
            with lock: metrics['analysis_requests'] += 1
            item = {'pages':[1], 'quote':'A field guide to slow reading', 'note':'Read this again', 'interpretation':'', 'kind':'handwriting'}
            return self.reply(200, {'stop_reason':'end_turn', 'content':[{'type':'text', 'text':json.dumps({'items':[item]})}]})
        if self.path == '/api/v3/save/':
            if self.headers.get('Authorization') != 'Token ui-test-token': return self.reply(401, {})
            if (payload.get('parent_id'), payload.get('content')) not in [('guide', 'A field guide to slow reading'), ('article', 'Writing helps us see what we think.')]: return self.reply(400, {})
            with lock:
                metrics['highlight_posts'] += 1
                identifier = 'highlight-' + str(metrics['highlight_posts'])
                highlights.append({'id':identifier,'parent_id':payload['parent_id'],'notes':payload.get('notes','')})
            return self.reply(201, {'id':identifier})
        return self.reply(404, {})

if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    print(json.dumps({'phase':'ready','port':PORT}), flush=True)
    server.serve_forever()
