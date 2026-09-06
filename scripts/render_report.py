"""Render the original Chinese Markdown report to a print-ready PDF on Windows."""
from pathlib import Path
import html
import re
from urllib.parse import quote

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Image, Table, TableStyle

ROOT = Path(__file__).resolve().parents[1]
pdfmetrics.registerFont(TTFont('Chinese', 'C:/Windows/Fonts/msyh.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('Code', 'C:/Windows/Fonts/consola.ttf'))
INK = colors.HexColor('#102236')
MUTED = colors.HexColor('#536a7e')
TEAL = colors.HexColor('#087f8c')
WIDTH = A4[0]-88
base = ParagraphStyle('body', fontName='Chinese', fontSize=10.2, leading=15.6,
                      wordWrap='CJK', textColor=INK, spaceAfter=8, alignment=TA_LEFT,
                      allowWidows=0, allowOrphans=0)
styles = {
    'body': base,
    'title': ParagraphStyle('title', parent=base, fontSize=23, leading=32, spaceAfter=15),
    'section': ParagraphStyle('section', parent=base, fontSize=16, leading=23,
                              textColor=TEAL, spaceBefore=15, spaceAfter=10, keepWithNext=True),
    'cell': ParagraphStyle('cell', parent=base, fontSize=8.0, leading=12, spaceAfter=0),
    'code': ParagraphStyle('code', parent=base, fontName='Code', fontSize=9,
                           leading=14, backColor=colors.HexColor('#edf4f7'), borderPadding=9),
}

def inline(value):
    value = html.escape(value)
    def link(match):
        label, url = match.groups()
        if not url.startswith(('http:', 'https:')):
            path = (ROOT/'docs'/html.unescape(url)).resolve().relative_to(ROOT).as_posix()
            url = 'https://github.com/wohuishuo/mips-cpu-lab/blob/main/'+quote(path)
        return f'<link href="{url}" color="#087f8c">{label}</link>'
    value = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, value)
    value = re.sub(r'`([^`]+)`', r'<font name="Code" size="9">\1</font>', value)
    return re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', value)

def furniture(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor('#cad8e1'))
    canvas.line(44, A4[1]-36, A4[0]-44, A4[1]-36)
    canvas.setFont('Chinese', 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(44, A4[1]-27, 'MIPS CPU LAB  /  从指令到电路')
    canvas.drawRightString(A4[0]-44, 25, f'实验报告 · {doc.page}')
    canvas.drawString(44, 25, 'wohuishuo/mips-cpu-lab · 实测与未验证边界分别记录')
    canvas.restoreState()

story = []
lines = (ROOT/'docs/report.md').read_text(encoding='utf-8').splitlines()
i = 0
while i < len(lines):
    line = lines[i].strip()
    i += 1
    if not line:
        continue
    if line.startswith('# '):
        story.append(Paragraph(inline(line[2:]), styles['title']))
    elif line.startswith('## '):
        story.append(Paragraph(inline(line[3:]), styles['section']))
    elif line.startswith('!['):
        relative = re.search(r'\]\(([^)]+)\)', line).group(1)
        picture = Image(str((ROOT/'docs'/relative).resolve()), width=WIDTH, height=WIDTH*9/16)
        story.extend([Spacer(1, 4), picture, Spacer(1, 12)])
    elif line.startswith('```'):
        code = []
        while i < len(lines) and not lines[i].startswith('```'):
            code.append(html.escape(lines[i])); i += 1
        i += 1
        story.append(Paragraph('<br/>'.join(code), styles['code']))
    elif line.startswith('|'):
        rows = [line]
        while i < len(lines) and lines[i].startswith('|'):
            rows.append(lines[i]); i += 1
        cells = [[Paragraph(inline(cell.strip()), styles['cell'])
                  for cell in row.strip('|').split('|')]
                 for row in rows if not re.match(r'^\|[\s:|\-]+\|$', row)]
        table = Table(cells, colWidths=[WIDTH*.20, WIDTH*.20, WIDTH*.12, WIDTH*.18, WIDTH*.30],
                      repeatRows=1, hAlign='LEFT')
        table.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#dceef1')),
            ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor('#f2f6f9')]),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('LEFTPADDING', (0,0), (-1,-1), 6), ('RIGHTPADDING', (0,0), (-1,-1), 6),
            ('TOPPADDING', (0,0), (-1,-1), 7), ('BOTTOMPADDING', (0,0), (-1,-1), 7),
            ('LINEBELOW', (0,0), (-1,0), .6, colors.HexColor('#92b7c0')),
        ]))
        story.extend([table, Spacer(1, 12)])
    else:
        paragraph = [line]
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(('#', '![', '|', '```')):
            paragraph.append(lines[i].strip()); i += 1
        story.append(Paragraph(inline(''.join(paragraph)), styles['body']))

output = ROOT/'docs/report.pdf'
doc = SimpleDocTemplate(str(output), pagesize=A4, leftMargin=44, rightMargin=44,
                        topMargin=53, bottomMargin=44, title='MIPS CPU 设计、验证与 FPGA 演示报告',
                        author='MIPS CPU Lab', pageCompression=1)
doc.build(story, onFirstPage=furniture, onLaterPages=furniture)
print(f'PASS REPORT_PDF {output.name}')
