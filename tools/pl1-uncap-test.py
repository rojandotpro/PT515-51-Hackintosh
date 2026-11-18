#!/usr/bin/env python3
"""PT515-51 PL1 uncap test — run from LINUX as root.

Why: Intel CPUs enforce the LOWER of two package power limits:
  * MSR 0x610             (what we raised before, from the kext)
  * MCHBAR + 0x59A0 (MMIO) (never touched — BIOS sets it to 45 W too)
If the MMIO copy is still 45 W, raising the MSR alone does nothing. This
script reads both and, with --write, raises BOTH to 65 W under full load and
measures real package power. Everything is restored on exit.

  sudo python3 pl1-uncap-test.py           # read-only report
  sudo python3 pl1-uncap-test.py --write   # 90 s load test at 65 W

Needs: kernel booted with  iomem=relaxed  (for /dev/mem MMIO access).
Safety: aborts and restores if package temp >= 95 C. PL2 is left at 75 W.
"""
import os, sys, struct, time, glob, mmap, subprocess, signal

PL1_W, TEMP_ABORT, DURATION = 65, 95, 90

def die(m): print("ERROR:", m); sys.exit(1)
if os.geteuid(): die("run with sudo")
subprocess.run(["modprobe", "msr"], check=False)

def rdmsr(r, cpu=0):
    with open(f"/dev/cpu/{cpu}/msr", "rb") as f: return struct.unpack("<Q", os.pread(f.fileno(), 8, r))[0]
def wrmsr_all(r, v):
    for p in glob.glob("/dev/cpu/[0-9]*/msr"):
        fd = os.open(p, os.O_WRONLY); os.pwrite(fd, struct.pack("<Q", v), r); os.close(fd)

def pci_cfg32(off):
    with open("/sys/bus/pci/devices/0000:00:00.0/config", "rb") as f:
        f.seek(off); return struct.unpack("<I", f.read(4))[0]
mch = ((pci_cfg32(0x4C) << 32) | pci_cfg32(0x48))
if not mch & 1: die("MCHBAR not enabled")
mch &= 0x7FFFFF8000
PG = mch + 0x5000                       # page holding 0x59A0
try:
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    mm = mmap.mmap(fd, 0x1000, offset=PG)
except OSError as e:
    die(f"/dev/mem refused ({e}). Reboot Linux with kernel parameter iomem=relaxed")
def rdmmio(): return struct.unpack("<Q", mm[0x9A0:0x9A8])[0]
def wrmmio(v): mm[0x9A0:0x9A8] = struct.pack("<Q", v)

unit = 1 / (1 << (rdmsr(0x606) & 0xF))
def fmt(v):
    return (f"PL1 {(v & 0x7FFF)*unit:5.1f} W en={v>>15&1}  "
            f"PL2 {((v>>32) & 0x7FFF)*unit:5.1f} W en={v>>47&1}  LOCK={v>>63}")
def set_pl1(v, w): return (v & ~0x7FFF) | (int(w / unit) & 0x7FFF) | (1 << 15)

msr0, mmio0 = rdmsr(0x610), rdmmio()
print(f"MCHBAR = {mch:#x}")
print(f"MSR  0x610      : {msr0:#018x}  {fmt(msr0)}")
print(f"MMIO MCHBAR+59A0: {mmio0:#018x}  {fmt(mmio0)}")
if "--write" not in sys.argv:
    print("\nRead-only. Re-run with --write to test 65 W under load."); sys.exit(0)
if mmio0 >> 63: print("\nMMIO limit is LOCKED (bit 63) — cannot be raised by software. Done."); sys.exit(0)

def energy(): return int(open(glob.glob("/sys/class/powercap/intel-rapl:0/energy_uj")[0]).read())
def temp():
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        if "x86_pkg_temp" in open(z + "/type").read(): return int(open(z + "/temp").read()) // 1000
    return -1
def mhz():
    f = [int(open(p).read()) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    return sum(f) // len(f) // 1000 if f else -1

load = [subprocess.Popen([sys.executable, "-c", "while 1: pass"]) for _ in range(os.cpu_count())]
def restore(*_):
    for p in load: p.kill()
    wrmsr_all(0x610, msr0); wrmmio(mmio0)
    print(f"\nrestored: MSR {rdmsr(0x610):#x}  MMIO {rdmmio():#x}"); sys.exit(0)
signal.signal(signal.SIGINT, restore); signal.signal(signal.SIGTERM, restore)

def sample(tag, secs):
    e0, t0 = energy(), time.time()
    for _ in range(secs // 3):
        time.sleep(3)
        e1, t1 = energy(), time.time()
        w = (e1 - e0) / 1e6 / (t1 - t0); e0, t0 = e1, t1
        m, x = rdmsr(0x610), rdmmio(); t = temp()
        print(f"[{tag}] {w:5.1f} W  {mhz()} MHz  {t} C   MSR PL1 {(m&0x7FFF)*unit:.0f} W   MMIO PL1 {(x&0x7FFF)*unit:.0f} W")
        if t >= TEMP_ABORT: print("TEMP ABORT"); restore()

print("\n--- baseline 30 s at stock limits (let PL2 burst expire) ---")
sample("stock", 30)
print(f"\n--- writing PL1 = {PL1_W} W to MSR and MMIO ---")
wrmsr_all(0x610, set_pl1(msr0, PL1_W)); wrmmio(set_pl1(mmio0, PL1_W))
sample(f"{PL1_W}W ", DURATION)
restore()
