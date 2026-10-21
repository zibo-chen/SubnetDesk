"""Build the offline review gallery and a portable delivery package."""
import hashlib
import html
import json
from pathlib import Path
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / 'manifest.json').read_text())
catalog = json.loads((ROOT / 'catalog.json').read_text())
assert {p['id'] for p in manifest} == {p['id'] for p in catalog['pages']}
assert len(manifest) == 43

groups = {
    '设备与发现': ['D01', 'D02', 'D03', 'D04', 'D05', 'M01', 'M02', 'M03', 'M04', 'M05'],
    '身份与连接': ['D06', 'D07', 'D08', 'D09', 'M06', 'M07', 'M08'],
    '会话与窗口': ['D10', 'D23', 'D24', 'M09'],
    '远控与工具': ['D11', 'D12', 'D13', 'D19', 'D20', 'D21', 'D25', 'M10', 'M11', 'M12', 'M13', 'M17', 'M18'],
    '本机与设置': ['D14', 'D15', 'D16', 'D17', 'D18', 'D22', 'M14', 'M15', 'M16'],
}
pages = []
for page in manifest:
    source = ROOT / page['file']
    assert source.is_file(), source
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    assert digest == page['sha256'], page['id']
    with Image.open(source) as im:
        assert list(im.size) == page['dimensions']
        im.verify()
    group = next(name for name, ids in groups.items() if page['id'] in ids)
    pages.append({key: page[key] for key in ['id', 'platform', 'title', 'ux', 'file', 'dimensions', 'sha256']} | {'group': group})

(ROOT / 'pages.json').write_text(json.dumps(pages, ensure_ascii=False, indent=2) + '\n')
page_table = '| 编号 | 页面原图 | UX 重点 |\n| --- | --- | --- |\n'
page_table += '\n'.join(f"| {p['id']} | [{p['title']}]({p['file']}) | {p['ux']} |" for p in pages)
readme = ROOT / 'README.md'
prefix = readme.read_text().split('<!-- PAGE_CATALOG -->')[0]
readme.write_text(prefix + '<!-- PAGE_CATALOG -->\n\n' + page_table + '\n')

template = r'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SubnetDesk · 43 页 UI / UX 图册</title>
<style>
:root{color-scheme:light;--bg:#f8f5f0;--ink:#332b3b;--muted:#716b78;--lilac:#ddd7ee;--line:#e4dfe5;--panel:#fffdfa}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}button,input,select{font:inherit}button,a,input,select{touch-action:manipulation}a{color:inherit;text-underline-offset:4px}button{cursor:pointer}button:disabled{opacity:.35;cursor:default}:focus-visible{outline:3px solid #786391;outline-offset:4px}button,input,select{border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--ink)}button{padding:10px 17px;min-height:44px}button:hover:not(:disabled){background:#eee8f3}input{padding:11px 16px;min-height:48px}select{padding:10px 13px;min-height:48px}.wrap{max-width:1600px;margin:auto;padding:0 40px}.top{display:flex;justify-content:space-between;gap:20px;padding-top:27px;align-items:center}.brand{font-size:25px;font-weight:750;letter-spacing:-1px}.meta{color:var(--muted);font-size:13px}.links{display:flex;gap:24px}.hero{padding:44px 0 28px}.eyebrow{color:var(--muted);font-size:13px;letter-spacing:2px}.hero h1{font-size:clamp(30px,3.8vw,49px);letter-spacing:-1.5px;line-height:1.2;margin:10px 0 15px;font-weight:650}.hero p{max-width:850px;margin:0;color:var(--muted);font-size:16px}.featured{display:flex;gap:9px;flex-wrap:wrap;margin-top:22px}.featured button{font-size:13px;background:transparent}.controls{position:sticky;top:0;z-index:4;background:rgba(248,245,240,.97);border-top:1px solid var(--line);border-bottom:1px solid var(--line);padding:16px 0;display:flex;gap:12px;align-items:center;flex-wrap:wrap}.segments{display:flex;gap:3px;padding:4px;background:#eae5ec;border-radius:14px}.segments button{border:0;background:transparent;padding:7px 16px;min-height:40px}.segments button[aria-pressed=true]{background:var(--ink);color:white}.controls input{flex:1;min-width:170px}.count{font-size:13px;color:var(--muted);white-space:nowrap}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:26px;padding:28px 0 52px}.card{border:1px solid var(--line);border-radius:19px;overflow:hidden;background:var(--panel);min-width:0}.image-btn{display:block;width:100%;padding:16px;border:0;border-radius:0;min-height:0;background:#eeeaf0}.image-btn:hover:not(:disabled){background:#e5deec}.image-btn img{display:block;width:100%;height:270px;object-fit:contain;filter:drop-shadow(0 3px 5px #332b3b0a)}.card.mobile .image-btn img{height:330px}.card-body{padding:18px 20px 22px}.card-meta{font-size:12px;color:var(--muted);display:flex;justify-content:space-between;gap:12px}.card h2{font-size:19px;margin:7px 0 6px;line-height:1.4}.card p{font-size:14px;margin:0;color:var(--muted);min-height:45px}.empty{grid-column:1/-1;padding:70px 0;text-align:center;color:var(--muted)}footer{border-top:1px solid var(--line);padding:22px 0 35px;font-size:13px;color:var(--muted)}dialog{border:0;border-radius:0;padding:0;margin:0;width:100vw;height:100dvh;max-width:100vw;max-height:100dvh;background:#f0ebf1;color:var(--ink)}dialog::backdrop{background:#f0ebf1}.viewer{height:100%;display:flex;flex-direction:column}.viewer-head{padding:10px 20px;display:flex;gap:12px;align-items:center;background:var(--panel);border-bottom:1px solid var(--line);flex-shrink:0}.viewer-title{flex:1;min-width:0}.viewer-title strong{display:block;font-size:16px}.viewer-title span{font-size:12px;color:var(--muted)}.viewer-head button,.viewer-head a{font-size:13px;white-space:nowrap}.viewer-head a{padding:9px 12px}.viewer-note{margin:0;padding:9px 22px;color:var(--muted);font-size:13px;flex-shrink:0;background:var(--bg)}.stage{flex:1;min-height:0;overflow:auto;display:grid;place-items:center;padding:16px}.stage img{display:block;max-width:100%;max-height:100%;object-fit:contain}.stage.original{display:block}.stage.original img{max-width:none;max-height:none;margin:0 auto}.viewer-bottom{display:flex;justify-content:center;align-items:center;gap:20px;padding:9px;background:var(--panel);flex-shrink:0}.viewer-bottom span{font-size:12px;color:var(--muted)}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}
@media(min-width:1700px){.grid{grid-template-columns:repeat(4,minmax(0,1fr))}}
@media(max-width:1000px){.wrap{padding:0 24px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.image-btn img{height:230px}.links{gap:15px}.meta{display:none}}
@media(max-width:600px){.wrap{padding:0 18px}.top{padding-top:18px}.brand{font-size:21px}.links{font-size:13px}.hero{padding:30px 0 24px}.hero p{font-size:14px}.grid{grid-template-columns:1fr;gap:20px}.controls{gap:9px}.segments{width:100%}.segments button{flex:1}.controls select{max-width:145px}.count{width:100%;text-align:right}.card.mobile .image-btn img{height:430px}.image-btn img{height:auto;max-height:330px}.viewer-head{flex-wrap:wrap;padding:9px 12px}.viewer-title{flex-basis:calc(100% - 95px)}.viewer-head a,.viewer-head button{padding:8px 12px}.viewer-note{padding:8px 12px;font-size:12px}.stage{padding:8px}.viewer-bottom{gap:14px}}
@media(prefers-reduced-motion:no-preference){.card{transition:border-color .15s}.card:hover{border-color:#bcb0c7}}
.stage:not(.original) img{position:absolute;inset:16px;width:calc(100% - 32px);height:calc(100% - 32px);max-width:none;max-height:none;object-fit:contain}.stage{position:relative}.stage.original img{position:static;width:auto;height:auto}body:has(dialog[open]){overflow:hidden}
@media(max-width:600px){.stage:not(.original) img{inset:8px;width:calc(100% - 16px);height:calc(100% - 16px)}}
</style>
</head>
<body>
<div class="wrap">
<header class="top"><div class="brand">SubnetDesk <span class="meta">／ UI &amp; UX</span></div><nav class="links" aria-label="交付文件"><a href="README.md">设计说明</a><a href="SubnetDesk-UI-43-pages.zip" download>下载整套原图</a></nav></header>
<section class="hero"><div class="eyebrow">方案二 · 完整页面延展</div><h1>连接很轻，操作很近。</h1><p>25 张桌面图、18 张移动图。统一 Logo 与圆角线性图标，让远程画面成为主角。每张图只呈现一个页面或一个交互状态。</p><div class="featured"><button data-jump="D11">远控 · 工具栏展开</button><button data-jump="D25">远控 · 自动隐藏</button><button data-jump="D23">标签拆分</button><button data-jump="D24">窗口合并</button><button data-jump="M11">移动横屏</button></div></section>
<section class="controls" aria-label="筛选页面"><div class="segments" role="group" aria-label="平台"><button data-platform="all" aria-pressed="true">全部 43</button><button data-platform="desktop" aria-pressed="false">桌面 25</button><button data-platform="mobile" aria-pressed="false">移动 18</button></div><label class="sr" for="search">搜索页面名称、编号或功能</label><input id="search" type="search" placeholder="搜索页面、编号或功能…"><label class="sr" for="group">页面类别</label><select id="group"><option value="all">所有功能</option>__GROUP_OPTIONS__</select><span id="count" class="count" aria-live="polite"></span></section>
<main id="grid" class="grid"></main>
<footer>2026-10-20 · 静态设计稿，图片中的设备与数据为示例。窗口拆合、自动隐藏等行为规范见设计说明；本图册不建立远程连接。</footer>
</div>
<dialog id="dialog" aria-label="页面原图查看器"><div class="viewer"><div class="viewer-head"><div class="viewer-title"><strong id="viewer-title"></strong><span id="viewer-meta"></span></div><button id="zoom" aria-pressed="false">原始尺寸</button><a id="original" target="_blank" rel="noopener">打开原图 ↗</a><button id="close">关闭 Esc</button></div><p id="viewer-note" class="viewer-note"></p><div id="stage" class="stage"><img id="viewer-image" alt=""></div><div class="viewer-bottom"><button id="prev" aria-label="上一页">← 上一页</button><span id="position" aria-live="polite"></span><button id="next" aria-label="下一页">下一页 →</button></div></div></dialog>
<script id="page-data" type="application/json">__PAGE_DATA__</script>
<script>
const pages=JSON.parse(document.querySelector('#page-data').textContent);
if(location.protocol==='file:')document.querySelector('[download]').hidden=true;
const $=s=>document.querySelector(s);
const grid=$('#grid'),dialog=$('#dialog');let platform='all',filtered=[...pages],viewerPages=[],current=0,opener=null;
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text)n.textContent=text;return n}
function render(){const query=$('#search').value.trim().toLowerCase(),group=$('#group').value;filtered=pages.filter(p=>(platform==='all'||p.platform===platform)&&(group==='all'||p.group===group)&&[p.id,p.title,p.ux,p.group,p.file].join(' ').toLowerCase().includes(query));grid.replaceChildren();$('#count').textContent=`${filtered.length} / 43 页`;
for(const p of filtered){const card=el('article',`card ${p.platform}`);card.id=`page-${p.id}`;const button=el('button','image-btn');button.setAttribute('aria-label',`放大 ${p.id} ${p.title}`);const im=el('img');im.src=p.file;im.alt=`${p.id} ${p.title}设计稿`;im.loading='lazy';im.width=p.dimensions[0];im.height=p.dimensions[1];button.append(im);button.addEventListener('click',()=>openPage(p.id,button,filtered));const body=el('div','card-body'),meta=el('div','card-meta');meta.append(el('span','',`${p.id} · ${p.platform==='desktop'?'桌面端':'移动端'}`),el('span','',p.group));body.append(meta,el('h2','',p.title),el('p','',p.ux));card.append(button,body);grid.append(card)}if(!filtered.length)grid.append(el('p','empty','没有匹配页面，试试其他关键词或类别。'))}
function show(){const p=viewerPages[current];$('#viewer-title').textContent=`${p.id} · ${p.title}`;$('#viewer-meta').textContent=`${p.platform==='desktop'?'桌面端':'移动端'} · ${p.dimensions.join(' × ')} px · ${p.group}`;$('#viewer-note').textContent=p.ux;$('#viewer-image').src=p.file;$('#viewer-image').alt=`${p.id} ${p.title}完整设计稿`;$('#original').href=p.file;$('#position').textContent=`${current+1} / ${viewerPages.length}`;$('#prev').disabled=current===0;$('#next').disabled=current===viewerPages.length-1;$('#stage').classList.remove('original');$('#zoom').setAttribute('aria-pressed','false');$('#zoom').textContent='原始尺寸';$('#stage').scrollTop=0;$('#stage').scrollLeft=0;history.replaceState(null,'',`#${p.id}`)}
function openPage(id,from,list=pages){viewerPages=[...list];current=viewerPages.findIndex(p=>p.id===id);if(current<0)return;opener=from||document.activeElement;show();if(!dialog.open)dialog.showModal();$('#close').focus()}
function move(delta){const n=current+delta;if(n<0||n>=viewerPages.length)return;current=n;show()}
function finish(){history.replaceState(null,'',location.pathname+location.search);opener?.focus()}
$('#close').addEventListener('click',()=>dialog.close());dialog.addEventListener('close',finish);$('#prev').addEventListener('click',()=>move(-1));$('#next').addEventListener('click',()=>move(1));$('#zoom').addEventListener('click',()=>{const v=$('#stage').classList.toggle('original');$('#zoom').setAttribute('aria-pressed',String(v));$('#zoom').textContent=v?'适应窗口':'原始尺寸'});
document.addEventListener('keydown',e=>{if(!dialog.open)return;if(e.key==='ArrowLeft'){e.preventDefault();move(-1)}if(e.key==='ArrowRight'){e.preventDefault();move(1)}});
document.querySelectorAll('[data-platform]').forEach(b=>b.addEventListener('click',()=>{platform=b.dataset.platform;document.querySelectorAll('[data-platform]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));$('#search').addEventListener('input',render);$('#group').addEventListener('change',render);document.querySelectorAll('[data-jump]').forEach(b=>b.addEventListener('click',()=>openPage(b.dataset.jump,b)));render();const initial=location.hash.slice(1);if(pages.some(p=>p.id===initial))openPage(initial,null);
</script>
</body></html>'''

data = json.dumps(pages, ensure_ascii=False).replace('</', '<\/')
options = ''.join(f'<option>{html.escape(name)}</option>' for name in groups)
(ROOT / 'index.html').write_text(template.replace('__GROUP_OPTIONS__', options).replace('__PAGE_DATA__', data))

delivery_files = ['index.html', 'README.md', 'pages.json', 'design-tokens.json']
delivery_files += [p['file'] for p in pages]
delivery_files += ['references/approved-home.png', 'references/approved-logo.png', 'references/approved-remote-layout.png']
archive = ROOT / 'SubnetDesk-UI-43-pages.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as z:
    for name in delivery_files:
        z.write(ROOT / name, 'SubnetDesk-UI-43-pages/' + name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len([n for n in z.namelist() if '/desktop/' in n or '/mobile/' in n]) == 43
    assert not any('.previous.' in n for n in z.namelist())
print(json.dumps({'pages': len(pages), 'desktop': sum(p['platform'] == 'desktop' for p in pages), 'mobile': sum(p['platform'] == 'mobile' for p in pages), 'gallery': str(ROOT / 'index.html'), 'zip': str(archive), 'zipMiB': round(archive.stat().st_size / 1048576, 1)}, ensure_ascii=False))
