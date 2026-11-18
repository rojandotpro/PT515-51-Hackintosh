import re,base64,plistlib,sys,os
EFI=os.path.expanduser('~/mnt/Volumes--EFI/EFI/OC/config.plist')
txt=open(EFI,encoding='utf-8').read()
m=re.search(r'(<key>AAPL00,override-no-connect</key>\s*<data>)([^<]*)(</data>)',txt)
cur=base64.b64decode(re.sub(r'\s+','',m.group(2)))
assert len(cur)==128
open('EDID-installed-128.bin','wb').write(cur)
def dtd(b):
    clk=(b[0]|b[1]<<8)/100
    ha=b[2]|(b[4]>>4)<<8; hb=b[3]|(b[4]&15)<<8
    va=b[5]|(b[7]>>4)<<8; vb=b[6]|(b[7]&15)<<8
    return clk,ha,hb,va,vb,clk*1e6/((ha+hb)*(va+vb))
def show(e,tag):
    print(tag,len(e),'sum%256=',sum(e)%256)
    for off in (54,72,90,108):
        d=e[off:off+18]
        if d[0]|d[1]: print('  DTD@%d'%off,'%.3f MHz %dx%d htot=%d vtot=%d -> %.3f Hz'%(dtd(d)[0],dtd(d)[1],dtd(d)[3],dtd(d)[1]+dtd(d)[2],dtd(d)[3]+dtd(d)[4],dtd(d)[5]))
        else: print('  desc@%d'%off,d[3:].decode('latin1').strip())
    if len(e)>128:
        x=e[128:]; print('  ext tag',hex(x[0]),'rev',x[1],'dtdoff',x[2])
        o=x[2]
        while o+18<=127 and (x[o]|x[o+1]):
            d=x[o:o+18]; print('  extDTD','%.3f MHz vtot=%d -> %.3f Hz'%(dtd(d)[0],dtd(d)[3]+dtd(d)[4],dtd(d)[5])); o+=18
show(cur,'installed')
t=bytearray(cur[72:90])      # 60Hz DTD as template (same clock/htotal)
htot=(t[2]|(t[4]>>4)<<8)+(t[3]|(t[4]&15)<<8); clk=(t[0]|t[1]<<8)*1e4
vt=round(clk/(htot*90)); vb=vt-1080
t[6]=vb&255; t[7]=(t[7]&0xF0)|(vb>>8)
t[17]=0x1a
d90=bytes(t)
def fix(b):
    b=bytearray(b); b[127]=(-sum(b[:127]))%256; return bytes(b)
# A: 256-byte, 90Hz in CTA extension block
a=bytearray(cur); a[89]=0x1a; a[126]=1; a=fix(a)
ext=bytearray(128); ext[0]=2; ext[1]=3; ext[2]=4; ext[3]=0; ext[4:22]=d90; ext=fix(ext)
A=bytes(a)+bytes(ext)
# B: 128-byte, 90Hz replaces the 60Hz slot
b=bytearray(cur); b[72:90]=d90; B=fix(b)
for n,e in (('A-ext256',A),('B-replace60',B)):
    open('EDID-90hz-%s.bin'%n,'wb').write(e); show(e,n)
    assert sum(e[:128])%256==0 and (len(e)<256 or sum(e[128:])%256==0)
    newtxt=txt[:m.start(2)]+base64.b64encode(e).decode()+txt[m.end(2):]
    plistlib.loads(newtxt.encode())
    open('config.%s.plist'%n,'w',encoding='utf-8').write(newtxt)
print('90Hz DTD',d90.hex())
