import json,sys
from collections import deque
def load(mp):
    m=json.load(open('game/assets/maps/%s.json'%mp))
    ts=json.load(open('game/assets/tilesets/%s.json'%m['tileset']))
    W,H=m['width'],m['height']; bd=ts['blocks']; walk=set(ts['walkable_tiles'])
    tile=[[0]*(W*4) for _ in range(H*4)]
    for by in range(H):
        for bx in range(W):
            b=bd[m['blocks'][by][bx]]
            for ty in range(4):
                for tx in range(4): tile[by*4+ty][bx*4+tx]=b[ty*4+tx]
    return m,tile,walk,W*2,H*2
PAIRS=[(0x20,0x05),(0x41,0x05),(0x2A,0x05),(0x05,0x21)]
m,tile,walk,CW,CH=load('VictoryRoad1F')
def feet(c): return tile[c[1]*2+1][c[0]*2]
# Only the up-ladder (1,1) blocks standing. The entrance warps (8,17),(9,17) are STANDABLE: VR1F uses
# ExtraWarpCheck "function 1" (IsPlayerFacingEdgeOfMap), so a warp fires only when you step toward the map
# edge (facing south) — you can stand on them facing inward to push a boulder up. This is gh #80: the port
# currently fires warps on any step onto a warp tile, which would eject you here. Treating them as solid
# made the solver report NO SOLUTION; treating them standable finds the real StrategyWiki route.
WARPS={(1,1)}
def walkable(c):
    x,y=c
    if (x,y) in WARPS: return False
    return 0<=x<CW and 0<=y<CH and feet(c) in walk
def tpblk(a,b):
    s,f=feet(a),feet(b); return any((s==x and f==y)or(s==y and f==x) for x,y in PAIRS)
DIRS={0:(0,1),1:(0,-1),2:(-1,0),3:(1,0)}  # DOWN UP LEFT RIGHT (port enum)
DN={0:'DOWN',1:'UP',2:'LEFT',3:'RIGHT'}
ALLB={(5,15),(14,2),(2,10)}
SWITCH=(17,13); START=(8,16)
def reachable(player, boulder, others):
    obst=others|{boulder}
    seen={player}; q=deque([player])
    while q:
        c=q.popleft()
        for d in DIRS.values():
            n=(c[0]+d[0],c[1]+d[1])
            if n in seen or not walkable(n) or n in obst or tpblk(c,n): continue
            seen.add(n); q.append(n)
    return seen
def solve(boulder):
    others=ALLB-{boulder}
    # state: boulder pos; keep player-normalized as reachable-set signature
    start_reach=frozenset(reachable(START,boulder,others))
    init=(boulder, start_reach)
    seen={boulder}; q=deque([(boulder,START,[])])
    # store best by boulder pos (player region derived)
    visited={boulder:frozenset([START])}
    q=deque([(boulder,frozenset(reachable(START,boulder,others)),[])])
    seenb={(boulder,)}
    while q:
        b,region,path=q.popleft()
        if b==SWITCH: return path
        for d,(dx,dy) in DIRS.items():
            behind=(b[0]-dx,b[1]-dy)         # player stands here to push in dir d
            ahead=(b[0]+dx,b[1]+dy)          # boulder moves here
            if not walkable(ahead) or ahead in others: continue
            if behind not in region: continue
            nb=ahead
            nregion=frozenset(reachable(b,nb,others))  # after push, player is at old boulder cell b
            key=(nb, nregion)
            if key in seenb: continue
            seenb.add(key)
            q.append((nb,nregion,path+[(b,d)]))
    return None
for boulder in sorted(ALLB):
    p=solve(boulder)
    if p:
        # compress consecutive same-dir pushes into [from,dir,times]
        legs=[]; 
        for frm,d in p:
            if legs and legs[-1][1]==d and (legs[-1][0][0]+DIRS[d][0]*legs[-1][2], legs[-1][0][1]+DIRS[d][1]*legs[-1][2])==frm:
                legs[-1][2]+=1
            else: legs.append([frm,d,1])
        print('boulder %s -> SWITCH in %d pushes:'%(str(boulder),len(p)))
        for frm,d,t in legs:
            print('   [Vector2i%s, %d, %d],   # %s x%d'%(str(frm),d,t,DN[d],t))
    else:
        print('boulder %s -> SWITCH: NO SOLUTION'%str(boulder))
