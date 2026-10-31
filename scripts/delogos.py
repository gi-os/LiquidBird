# delogos.py <in.x> <out.m>: turn a Logos file into plain ObjC for a clang -fsyntax-only -Werror check.
# %hook -> a uniquely named category, %orig -> a zero of the method's return type (arguments still evaluated),
# %init -> (void)0, %ctor -> a constructor. Hooked classes the file doesn't declare get a stand-in @interface.
import re, sys
src = open(sys.argv[1]).read()
declared = set(re.findall(r'@interface\s+(\w+)\s*[:(]', src))
out, stack, n, ret, extra = [], [], 0, 'void', []
def zero(t):
    t = t.strip()
    if t == 'void': return None
    if '*' in t or t in ('id', 'instancetype', 'Class', 'SEL') or t.startswith('id<') or t.startswith('id <'): return 'nil'
    if t in ('BOOL', 'NSInteger', 'NSUInteger', 'CGFloat', 'double', 'float', 'int', 'long', 'UIInterfaceOrientationMask', 'UIStatusBarStyle'): return '(%s)0' % t
    return '(%s){0}' % t
def sub_orig(line):
    while '%orig' in line:
        i = line.index('%orig'); j = i + 5
        z = zero(ret)
        if j < len(line) and line[j] == '(':
            depth, k = 0, j
            while True:
                if line[k] == '(': depth += 1
                elif line[k] == ')':
                    depth -= 1
                    if depth == 0: break
                k += 1
            args, parts, d0, start = line[j + 1:k], [], 0, 0
            for q, ch in enumerate(args):
                if ch in '([{': d0 += 1
                elif ch in ')]}': d0 -= 1
                elif ch == ',' and d0 == 0: parts.append(args[start:q]); start = q + 1
            parts.append(args[start:])
            ev = '; '.join('(void)(%s)' % a for a in parts if a.strip())
            rep = '({ %s; })' % ev if z is None else '({ %s; %s; })' % (ev, z)
            line = line[:i] + rep + line[k + 1:]
        else:
            line = line[:i] + ('((void)0)' if z is None else '(' + z + ')') + line[j:]
    return line
for line in src.split('\n'):
    s = line.strip()
    m = re.match(r'%group\s+(\w+)', s)
    if m: stack.append('group'); out.append(''); continue
    m = re.match(r'%hook\s+(\w+)', s)
    if m:
        cls = m.group(1); stack.append('hook'); n += 1
        if cls not in declared:
            base = 'UIViewController' if 'Controller' in cls else 'UIView' if ('View' in cls or 'Window' in cls or 'Bar' in cls or 'Pill' in cls or 'Button' in cls) else 'NSObject'
            if not cls.startswith('UI') or cls in ('UILayoutContainerView',): extra.append('@interface %s : %s\n@end' % (cls, base)); declared.add(cls)
        out.append('@implementation %s (LBHook%d)' % (cls, n)); continue
    if s == '%end':
        out.append('@end' if stack.pop() == 'hook' else ''); continue
    if s.startswith('%ctor'):
        out.append('__attribute__((constructor)) static void LBCtor_%d(void) {' % n); continue
    m = re.match(r'\s*[-+]\s*\(([^)]*(?:\([^)]*\))?[^)]*)\)', line)
    if m and stack and stack[-1] == 'hook': ret = m.group(1)
    line = re.sub(r'%init\(\w+\)', '(void)0', line).replace('%init;', '(void)0;')
    out.append(sub_orig(line))
text = '\n'.join(out)
# stand-in declarations go right after the imports
imports_end = max(text.rfind('#import'), 0)
nl = text.index('\n', imports_end) + 1 if '#import' in text else 0
open(sys.argv[2], 'w').write(text[:nl] + '\n'.join(extra) + '\n' + text[nl:])
