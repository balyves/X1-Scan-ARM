# -*- coding: utf-8 -*-
# X1-Scan-ARM : capture lldb v3 (lecture seule). Commandes, reponses lues
# au retour de l'execution, statut SCSI, et donnees image enregistrees.
import lldb, os
RAW = os.path.expanduser('~/Desktop/x1-apercu.raw')
S = {'buf': 0, 'n': 0, 'dir': 0, 'k': 0, 'cdb': '', 'pending': False,
     'raw_off': 0, 'sync': 0, 'async': 0}

def _hex(b):
    return ' '.join('%02x' % x for x in bytearray(b))

def _rd(p, addr, size):
    e = lldb.SBError()
    b = p.ReadMemory(addr, size, e)
    return b if e.Success() else None

def _u(p, addr, size):
    e = lldb.SBError()
    return p.ReadUnsignedFromMemory(addr, size, e)

def _dump(p, count, status):
    S['pending'] = False
    line = '   FIN statut=0x%02x recus=%d' % (status, count) if status is not None else '   FIN (async)'
    print(line)
    if S['dir'] == 2 and S['buf'] and count:
        if S['cdb'].startswith('28'):
            b = _rd(p, S['buf'], count)
            if b is not None:
                with open(RAW, 'ab') as f:
                    f.write(b)
                print('   RAW offset=%d taille=%d' % (S['raw_off'], count))
                S['raw_off'] += count
                print('   REP ' + _hex(b[:64]))
        else:
            b = _rd(p, S['buf'], min(count, 64))
            if b is not None:
                print('   REP ' + _hex(b))

def on_cdb(frame, bp_loc, d):
    p = frame.GetThread().GetProcess()
    if S['pending']:
        _dump(p, S['n'], None)
    esp = frame.FindRegister('esp').GetValueAsUnsigned()
    ptr = _u(p, esp + 8, 4)
    size = _u(p, esp + 12, 1)
    b = _rd(p, ptr, size)
    S['k'] += 1
    S['cdb'] = _hex(b) if b else '?'
    S['dir'] = 0
    print('%04d CDB %s' % (S['k'], S['cdb']))
    return False

def on_sg(frame, bp_loc, d):
    p = frame.GetThread().GetProcess()
    esp = frame.FindRegister('esp').GetValueAsUnsigned()
    ranges = _u(p, esp + 8, 4)
    n = _u(p, esp + 16, 8)
    direction = _u(p, esp + 24, 1)
    addr = _u(p, ranges, 4) if ranges else 0
    S['buf'], S['n'], S['dir'] = addr, n, direction
    tag = {0: '--', 1: '->X1', 2: '<-X1'}.get(direction, str(direction))
    print('     %s %d octets' % (tag, n))
    if direction == 1 and addr and n:
        b = _rd(p, addr, min(n, 128))
        if b is not None:
            print('   ENV ' + _hex(b))
    return False

def on_sync(frame, bp_loc, d):
    th = frame.GetThread(); p = th.GetProcess(); t = p.GetTarget()
    esp = frame.FindRegister('esp').GetValueAsUnsigned()
    ret = _u(p, esp, 4)
    S['st_ptr'] = _u(p, esp + 12, 4)
    S['cnt_ptr'] = _u(p, esp + 16, 4)
    S['sync'] += 1
    S['armed'] = True
    rets = S.setdefault('rets', set())
    if ret not in rets:
        rets.add(ret)
        bp = t.BreakpointCreateByAddress(ret)
        bp.SetScriptCallbackFunction('cap3.after_sync')
    return False

def after_sync(frame, bp_loc, d):
    if not S.get('armed'):
        return False
    S['armed'] = False
    p = frame.GetThread().GetProcess()
    st = _u(p, S['st_ptr'], 4) if S.get('st_ptr') else None
    cnt = _u(p, S['cnt_ptr'], 8) if S.get('cnt_ptr') else S['n']
    _dump(p, cnt, st)
    return False

def on_async(frame, bp_loc, d):
    S['async'] += 1
    S['pending'] = True
    return False

def __lldb_init_module(debugger, d):
    if os.path.exists(RAW):
        os.remove(RAW)
    t = debugger.GetSelectedTarget()
    for name, fn in (('SCSITaskClass::sSetCommandDescriptorBlock', 'on_cdb'),
                     ('SCSITaskClass::sSetScatterGatherEntries', 'on_sg'),
                     ('SCSITaskClass::sExecuteTaskSync', 'on_sync'),
                     ('SCSITaskClass::sExecuteTaskAsync', 'on_async')):
        b = t.BreakpointCreateByName(name)
        b.SetScriptCallbackFunction('cap3.' + fn)
    print('cap3.py : points d arret poses, donnees image vers ' + RAW)
