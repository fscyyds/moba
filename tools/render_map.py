import json, math, random
from PIL import Image, ImageDraw

MAP_W, MAP_H = 10000, 10000
SCALE = 0.15  # 1500x1500 output
W, H = int(MAP_W * SCALE), int(MAP_H * SCALE)

img = Image.new('RGBA', (W, H), (34, 68, 30, 255))
draw = ImageDraw.Draw(img)

def w2s(x, y):
    return (int(x * SCALE), int(y * SCALE))

with open('/Users/shanli/Desktop/moba/server/map.json') as f:
    data = json.load(f)

# Terrain - grass
for t in data.get('terrain', []):
    x1, y1 = w2s(t['x'], t['y'])
    x2, y2 = w2s(t['x'] + t['w'], t['y'] + t['h'])
    for i in range(400):
        gx, gy = random.randint(x1, x2-1), random.randint(y1, y2-1)
        r, g, b = 30+random.randint(0,25), 55+random.randint(0,30), 20+random.randint(0,20)
        draw.point((gx, gy), fill=(r, g, b, 255))

# Roads
for r in data.get('roads', []):
    x1, y1 = w2s(r['x'], r['y'])
    x2, y2 = w2s(r['x'] + r['w'], r['y'] + r['h'])
    draw.rectangle([x1, y1, x2, y2], fill=(138, 114, 90, 255))
    for i in range(x1, x2, 8):
        draw.line([(i, y1), (i, y2)], fill=(120, 98, 78, 160), width=1)

# Walls
for w in data.get('walls', []):
    x1, y1 = w2s(w['x'], w['y'])
    x2, y2 = w2s(w['x'] + w['w'], w['y'] + w['h'])
    draw.rectangle([x1, y1, x2, y2], fill=(80, 75, 70, 255))

# Bushes (dark green)
for b in data.get('bushes', []):
    x1, y1 = w2s(b['x'], b['y'])
    x2, y2 = w2s(b['x'] + b['w'], b['y'] + b['h'])
    draw.rounded_rectangle([x1, y1, x2, y2], radius=6, fill=(25, 80, 25, 200), outline=(15, 60, 15, 180), width=2)

# Towers
for t in data.get('towers', []):
    x, y = w2s(t['x'], t['y'])
    color = (60, 80, 220) if t['team'] == 0 else (220, 60, 60)
    size = 8 if t.get('isMain') else 6
    draw.rectangle([x-size, y-size*2, x+size, y], fill=color, outline=(255,255,255,200), width=1)
    # Glow
    for i in range(3):
        draw.ellipse([x-size-i*3, y-size*2-i*3, x+size+i*3, y+i*3], outline=color + (80,), width=1)

# Bases / Fountains
for b in data.get('bases', []):
    x, y = w2s(b['x'], b['y'])
    r = int(b['radius'] * SCALE)
    color = (40, 100, 240) if b['team'] == 0 else (240, 60, 50)
    for i in range(4, 0, -1):
        draw.ellipse([x-r-i*5, y-r-i*5, x+r+i*5, y+r+i*5], fill=color + (40,))
    draw.ellipse([x-r, y-r, x+r, y+r], fill=color + (180,), outline=(255,255,255,180), width=2)

for f in data.get('fountains', []):
    x, y = w2s(f['x'], f['y'])
    r = int(f['radius'] * SCALE)
    fc = (80, 160, 255) if f['team'] == 0 else (255, 120, 120)
    draw.ellipse([x-r, y-r, x+r, y+r], fill=fc + (100,), outline=fc + (200,), width=3)

# Monsters (dragon/baron)
for m in data.get('monsters', []):
    x, y = w2s(m['x'], m['y'])
    r = 6 if m['type'] == 'baron' else 5
    c = (160, 40, 200) if m['type'] == 'baron' else (220, 160, 40)
    draw.ellipse([x-r, y-r, x+r, y+r], fill=c + (230,))

# Teleports
for tp in data.get('teleports', []):
    x, y = w2s(tp['x'], tp['y'])
    draw.ellipse([x-4, y-4, x+4, y+4], fill=(100, 180, 255, 200), outline=(255,255,255,200), width=1)

# River (diagonal)
river_pts = [(1000,2000),(2500,3500),(4000,4800),(5000,5000),(6000,5200),(7500,6500),(9000,8000)]
for i in range(len(river_pts)-1):
    x1, y1 = w2s(*river_pts[i])
    x2, y2 = w2s(*river_pts[i+1])
    draw.line([(x1, y1), (x2, y2)], fill=(30, 110, 150, 160), width=35)
    draw.line([(x1, y1), (x2, y2)], fill=(60, 160, 200, 200), width=12)

# Border vignette
for i in range(30):
    a = 255 - i * 8
    draw.rectangle([i, i, W-i, H-i], outline=(25, 18, 12, a), width=1)

out_path = '/Users/shanli/Desktop/moba/tools/map_render.png'
img.save(out_path)
print(f"Saved: {out_path} ({W}x{H})")
