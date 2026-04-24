#!/usr/bin/env python3
"""
build_catalog.py — rebuild catalog.html from all metadata + thumbnail files
Usage: python3 scripts/build_catalog.py
"""

import json, os, glob
from collections import Counter

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
METADATA_DIR = os.path.join(PROJECT_DIR, "metadata")
THUMBNAILS_DIR = os.path.join(PROJECT_DIR, "thumbnails")
CATALOG_DIR = os.path.join(PROJECT_DIR, "catalog")
OUTPUT = os.path.join(CATALOG_DIR, "catalog.html")

out = []
for f in glob.glob(os.path.join(METADATA_DIR, "*.info.json")):
    if "favorites" in os.path.basename(f):
        continue
    try:
        with open(f) as fh:
            d = json.load(fh)
        vid_id = d.get("id", "")
        url = d.get("webpage_url", "")
        title = d.get("title", f"Video {vid_id}")
        local_thumb = os.path.join(THUMBNAILS_DIR, f"{vid_id}.jpg")
        thumb_rel = f"../thumbnails/{vid_id}.jpg"
        thumb = thumb_rel if os.path.exists(local_thumb) else d.get("thumbnail", "")
        dur = d.get("duration")
        dur_fmt = f"{int(dur)//60}:{int(dur)%60:02d}" if dur else ""
        tags = d.get("tags") or d.get("categories") or []
        tags = [t for t in tags if isinstance(t, str)][:8]
        views = d.get("view_count") or 0
        likes = d.get("like_count") or 0
        out.append({
            "url": url, "thumb": thumb, "title": title,
            "duration": dur_fmt, "duration_s": int(dur) if dur else 0,
            "key": vid_id, "tags": tags, "views": views, "likes": likes,
        })
    except Exception as e:
        print(f"Skipping {f}: {e}")

out.sort(key=lambda v: v["title"].lower())
# Escape </script> so embedded JSON can't break the inline script block
videos_json = json.dumps(out, ensure_ascii=False).replace("</", "<\\/")

tag_counts = Counter(t for v in out for t in v["tags"])
all_tags = sorted(t for t, c in tag_counts.items() if c >= 2)
tags_json = json.dumps(all_tags, ensure_ascii=False).replace("</", "<\\/")

os.makedirs(CATALOG_DIR, exist_ok=True)

html = f"""<!DOCTYPE html>
<html>
<head>
  <title>My Video Catalog</title>
  <meta charset="UTF-8">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: sans-serif; background: #111; color: #ddd; }}
    h1 {{ padding: 20px; font-size: 1.4em; color: #fff; display: inline-block; }}
    .toolbar {{ padding: 0 20px 16px; display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }}
    .toolbar input, .toolbar select {{ background: #222; border: 1px solid #444; color: #fff;
      padding: 8px 12px; border-radius: 6px; font-size: 13px; }}
    .toolbar input {{ width: 260px; }}
    .toolbar button {{ background: #2a2a2a; border: 1px solid #555; color: #ccc;
      padding: 8px 14px; border-radius: 6px; font-size: 13px; cursor: pointer; }}
    .toolbar button:hover {{ background: #383838; color: #fff; }}
    .toolbar button.active {{ border-color: #7af; color: #7af; }}
    .meta {{ padding: 0 20px 10px; color: #888; font-size: 0.9em; }}
    .tag-section {{ padding: 0 20px 12px; }}
    .tag-toggle {{ background: none; border: 1px solid #444; color: #888; font-size: 12px;
      padding: 4px 10px; border-radius: 6px; cursor: pointer; margin-bottom: 8px; }}
    .tag-toggle:hover {{ border-color: #7af; color: #7af; }}
    .tag-bar {{ display: none; flex-wrap: wrap; gap: 6px; }}
    .tag-bar.open {{ display: flex; }}
    .tag-pill {{ background: #222; border: 1px solid #444; color: #aaa; font-size: 11px;
      padding: 3px 8px; border-radius: 10px; cursor: pointer; user-select: none; }}
    .tag-pill:hover {{ border-color: #7af; color: #7af; }}
    .tag-pill.active {{ background: #1a2a3a; border-color: #7af; color: #7af; }}
    .grid {{ display: flex; flex-wrap: wrap; gap: 14px; padding: 20px; }}
    .card {{ width: 240px; background: #1e1e1e; border-radius: 8px; overflow: hidden;
      transition: transform 0.15s; position: relative; }}
    .card:hover {{ transform: scale(1.03); }}
    .thumb-wrap {{ position: relative; width: 100%; height: 135px; background: #333; }}
    .thumb-wrap img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
    .duration {{ position: absolute; bottom: 6px; right: 6px; background: rgba(0,0,0,0.75);
      color: #fff; font-size: 11px; padding: 2px 5px; border-radius: 3px; }}
    .fav-btn {{ position: absolute; top: 6px; right: 6px; background: rgba(0,0,0,0.6);
      border: none; font-size: 16px; line-height: 1; padding: 3px 5px; border-radius: 4px;
      cursor: pointer; color: #888; }}
    .fav-btn.starred {{ color: #fc3; }}
    .info {{ padding: 8px 10px 10px; }}
    .info a {{ color: #7af; font-size: 12px; text-decoration: none;
      display: -webkit-box; -webkit-line-clamp: 2;
      -webkit-box-orient: vertical; overflow: hidden; }}
    .info a:hover {{ color: #fff; }}
    .stats {{ color: #666; font-size: 10px; margin-top: 4px; }}
    .card-tags {{ display: flex; flex-wrap: wrap; gap: 4px; margin-top: 5px; }}
    .card-tag {{ background: #252525; color: #777; font-size: 10px;
      padding: 2px 6px; border-radius: 8px; cursor: pointer; }}
    .card-tag:hover {{ color: #7af; }}
    .hidden {{ display: none; }}
  </style>
</head>
<body>
  <h1>My Video Catalog</h1>
  <div class="toolbar">
    <input type="text" id="search" placeholder="Search titles..." oninput="applyFilters()">
    <select id="sort" onchange="applyFilters()">
      <option value="title">Sort: Title</option>
      <option value="duration">Sort: Duration</option>
      <option value="views">Sort: Views</option>
      <option value="likes">Sort: Likes</option>
    </select>
    <button id="favFilter" onclick="toggleFavFilter()">Starred only</button>
    <button onclick="exportJSON()">Export JSON</button>
    <button onclick="exportCSV()">Export CSV</button>
  </div>
  <div class="meta" id="count"></div>
  <div class="tag-section">
    <button class="tag-toggle" id="tagToggle" onclick="toggleTagBar()">Tags ▾</button>
    <div class="tag-bar" id="tagBar"></div>
  </div>
  <div class="grid" id="grid"></div>
  <script>
    const videos = {videos_json};
    const allTags = {tags_json};
    const grid = document.getElementById('grid');
    const BATCH = 50;

    const FAV_KEY = 'vcat_favs';
    let _ls;
    try {{ _ls = localStorage; }} catch(e) {{ _ls = null; }}
    const favs = new Set(JSON.parse((_ls && _ls.getItem(FAV_KEY)) || '[]'));
    const saveFavs = () => {{ try {{ _ls && _ls.setItem(FAV_KEY, JSON.stringify([...favs])); }} catch(e) {{}} }};

    let activeTags = new Set();
    let favFilterOn = false;
    let filtered = [];
    let rendered = 0;
    let scrollObserver = null;

    function toggleTagBar() {{
      const bar = document.getElementById('tagBar');
      const btn = document.getElementById('tagToggle');
      const open = bar.classList.toggle('open');
      btn.textContent = open ? 'Tags ▴' : 'Tags ▾';
    }}

    function updateFavBtn(btn, key) {{
      const starred = favs.has(key);
      btn.className = 'fav-btn' + (starred ? ' starred' : '');
      btn.textContent = starred ? '\u2605' : '\u2606';
    }}

    const tagBar = document.getElementById('tagBar');
    allTags.forEach(tag => {{
      const p = document.createElement('span');
      p.className = 'tag-pill';
      p.textContent = tag;
      p.onclick = () => {{
        activeTags.has(tag) ? activeTags.delete(tag) : activeTags.add(tag);
        p.classList.toggle('active', activeTags.has(tag));
        applyFilters();
      }};
      tagBar.appendChild(p);
    }});

    function toggleFavFilter() {{
      favFilterOn = !favFilterOn;
      document.getElementById('favFilter').classList.toggle('active', favFilterOn);
      applyFilters();
    }}

    function clearGrid() {{
      grid.replaceChildren();
    }}

    function applyFilters() {{
      const term = document.getElementById('search').value.toLowerCase();
      const sortBy = document.getElementById('sort').value;

      filtered = videos.filter(v =>
        v.title.toLowerCase().includes(term) &&
        (!favFilterOn || favs.has(v.key)) &&
        (activeTags.size === 0 || [...activeTags].every(t => v.tags.includes(t)))
      );

      filtered.sort((a, b) => {{
        if (sortBy === 'title')    return a.title.localeCompare(b.title);
        if (sortBy === 'duration') return b.duration_s - a.duration_s;
        if (sortBy === 'views')    return b.views - a.views;
        if (sortBy === 'likes')    return b.likes - a.likes;
        return 0;
      }});

      if (scrollObserver) scrollObserver.disconnect();
      clearGrid();
      rendered = 0;
      renderBatch();
      document.getElementById('count').textContent = filtered.length + ' videos';
      scrollObserver = new IntersectionObserver(entries => {{
        if (!entries[0].isIntersecting) return;
        renderBatch();
        if (rendered >= filtered.length) scrollObserver.disconnect();
      }}, {{ rootMargin: '400px' }});
      scrollObserver.observe(sentinel);
    }}

    function renderCard(v) {{
      const card = document.createElement('div');
      card.className = 'card';

      const link1 = document.createElement('a');
      link1.href = v.url;
      link1.target = '_blank';

      const thumbWrap = document.createElement('div');
      thumbWrap.className = 'thumb-wrap';

      const img = document.createElement('img');
      img.src = v.thumb;
      img.loading = 'lazy';
      img.onerror = () => {{ thumbWrap.style.background = '#444'; }};
      thumbWrap.appendChild(img);

      if (v.duration) {{
        const dur = document.createElement('span');
        dur.className = 'duration';
        dur.textContent = v.duration;
        thumbWrap.appendChild(dur);
      }}

      const favBtn = document.createElement('button');
      favBtn.title = 'Toggle starred';
      updateFavBtn(favBtn, v.key);
      favBtn.onclick = (e) => {{
        e.preventDefault();
        e.stopPropagation();
        favs.has(v.key) ? favs.delete(v.key) : favs.add(v.key);
        saveFavs();
        updateFavBtn(favBtn, v.key);
        if (favFilterOn) applyFilters();
      }};
      thumbWrap.appendChild(favBtn);

      link1.appendChild(thumbWrap);
      card.appendChild(link1);

      const info = document.createElement('div');
      info.className = 'info';

      const link2 = document.createElement('a');
      link2.href = v.url;
      link2.target = '_blank';
      link2.textContent = v.title;
      info.appendChild(link2);

      if (v.views || v.likes) {{
        const stats = document.createElement('div');
        stats.className = 'stats';
        const parts = [];
        if (v.views) parts.push(v.views.toLocaleString() + ' views');
        if (v.likes) parts.push(v.likes.toLocaleString() + ' likes');
        stats.textContent = parts.join(' \u00b7 ');
        info.appendChild(stats);
      }}

      if (v.tags.length) {{
        const tagRow = document.createElement('div');
        tagRow.className = 'card-tags';
        v.tags.forEach(tag => {{
          const t = document.createElement('span');
          t.className = 'card-tag';
          t.textContent = tag;
          t.onclick = () => {{
            activeTags.add(tag);
            tagBar.querySelectorAll('.tag-pill').forEach(p => {{
              if (p.textContent === tag) p.classList.add('active');
            }});
            applyFilters();
          }};
          tagRow.appendChild(t);
        }});
        info.appendChild(tagRow);
      }}

      card.appendChild(info);
      return card;
    }}

    function renderBatch() {{
      const frag = document.createDocumentFragment();
      const end = Math.min(rendered + BATCH, filtered.length);
      for (let i = rendered; i < end; i++) frag.appendChild(renderCard(filtered[i]));
      grid.appendChild(frag);
      rendered = end;
    }}

    const sentinel = document.createElement('div');
    sentinel.style.height = '1px';
    document.body.appendChild(sentinel);

    // --- Export ---
    function exportJSON() {{
      const blob = new Blob([JSON.stringify(filtered, null, 2)], {{type: 'application/json'}});
      triggerDownload(blob, 'catalog.json');
    }}
    function exportCSV() {{
      const rows = [['id','title','url','duration','views','likes','tags']];
      filtered.forEach(v => rows.push([v.key, v.title, v.url, v.duration, v.views, v.likes, v.tags.join(';')]));
      const csv = rows.map(r => r.map(c => '"' + String(c).replace(/"/g,'""') + '"').join(',')).join('\\n');
      triggerDownload(new Blob([csv], {{type: 'text/csv'}}), 'catalog.csv');
    }}
    function triggerDownload(blob, name) {{
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = name;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 100);
    }}

    applyFilters();
  </script>
</body>
</html>"""

with open(OUTPUT, "w") as fh:
    fh.write(html)
print(f"✓ {OUTPUT} written with {len(out)} videos")
