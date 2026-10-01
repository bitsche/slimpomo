import os, json
OUT='svg'; os.makedirs(OUT,exist_ok=True)
S='fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"'
TANK='<rect x="2.5" y="2.5" width="13" height="13" rx="3" %s/>'%S
CLIP='<defs><clipPath id="t"><rect x="2.5" y="2.5" width="13" height="13" rx="3"/></clipPath></defs>'
HORIZON='<clipPath id="h"><rect x="0" y="0" width="18" height="10.6"/></clipPath>'
def level_y(l):
    # water line y for level l in [0,1]: min 1.5 pt water, crest stays >= 1.5 pt below inner top
    return 13.25-(13.25-5.45)*l
def water(l,op=1.0):
    y=level_y(l)
    return '%s<path d="M0 %.2f q2 -1.4 4 0 t4 0 t4 0 t4 0 t4 0 V18 H0Z" fill="#000" fill-opacity="%.2f" clip-path="url(#t)"/>'%(CLIP,y,op)
def bars(y0=6,y1=12): return '<path d="M7 %s V%s M11 %s V%s" stroke="#000" stroke-width="1.8" stroke-linecap="round"/>'%(y0,y1,y0,y1)
def sun_cy(p):
    return 13.1-7.2*p
def sun(p,op=1.0):
    cy=sun_cy(p)
    return '<defs>%s</defs><circle cx="9" cy="%.4f" r="4" fill="#000" fill-opacity="%.2f" clip-path="url(#h)"/>'%(HORIZON,cy,op)
IDLE_WAVE='<path d="M4 12.5 q1.25 -1.2 2.5 0 t2.5 0 t2.5 0 t2.5 0" %s/>'%S
SEA='<path d="M2 13 q1.75 -1.3 3.5 0 t3.5 0 t3.5 0 t3.5 0" %s/>'%S
states={
 'idle':TANK+IDLE_WAVE,
 'work-running-10':water(.10)+TANK,
 'work-running-45':water(.45)+TANK,
 'work-running-90':water(.90)+TANK,
 'work-paused-45':water(.45,.4)+TANK+bars(),
 'break-running-05':sun(.05)+SEA,
 'break-running-50':sun(.50)+SEA,
 'break-running-95':sun(.95)+SEA,
 'break-paused-50':sun(.50,.4)+SEA+bars(4,10),
}
for k,v in states.items():
    open(f'{OUT}/menubar-{k}.svg','w').write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18">%s</svg>'%v)
json.dump(list(states),open('states.json','w'))
print('ok')
