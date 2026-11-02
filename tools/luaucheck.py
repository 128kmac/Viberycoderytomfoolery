#!/usr/bin/env python3
"""Minimal Luau syntax + scope checker for EB: Proxima.

Parses the Luau subset used by this project (Lua 5.1 + compound assignment,
`continue`, if-expressions, backtick strings, simple type annotations) and
reports syntax errors, reads/writes of undefined globals, and calls to unknown
members of the standard libraries (math, table, string, task, ...).

Usage: python3 tools/luaucheck.py <file-or-dir> [...]
"""
import os
import re
import sys

KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
    'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true',
    'until', 'while', 'continue',
}

GLOBALS = set('''
game workspace script plugin Instance Vector3 Vector2 Vector3int16 Vector2int16 CFrame Color3 BrickColor UDim UDim2
Enum Ray RaycastParams OverlapParams TweenInfo NumberSequence NumberSequenceKeypoint ColorSequence
ColorSequenceKeypoint NumberRange Rect PhysicalProperties Region3 Font task tick time wait delay spawn
typeof type print warn error assert pcall xpcall select pairs ipairs next tostring tonumber math string
table coroutine os utf8 bit32 debug require setmetatable getmetatable rawget rawset rawequal rawlen unpack
buffer DateTime Random Axes Faces shared _G SharedTable newproxy gcinfo elapsedTime settings UserSettings
version Content
'''.split())

LIBS = {
    'math': set('abs acos asin atan atan2 ceil clamp cos cosh deg exp floor fmod frexp huge ldexp log log10 '
                'max min modf noise pi pow rad random randomseed round sign sin sinh sqrt tan tanh lerp map isnan isinf isfinite'.split()),
    'table': set('clear clone concat create find foreach foreachi freeze getn insert isfrozen maxn move pack remove sort unpack'.split()),
    'string': set('byte char find format gmatch gsub len lower match rep reverse split sub upper pack packsize unpack'.split()),
    'task': set('cancel defer delay desynchronize synchronize spawn wait'.split()),
    'coroutine': set('close create isyieldable resume running status wrap yield'.split()),
    'os': set('clock date difftime time'.split()),
    'utf8': set('char charpattern codepoint codes graphemes len nfcnormalize nfdnormalize offset'.split()),
}


class LuauError(Exception):
    pass


TOKEN_RE = re.compile(r'''
    (?P<ws>[ \t\r]+) |
    (?P<nl>\n) |
    (?P<comment>--) |
    (?P<num>0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<op>\.\.\.|\.\.=|//=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|%=|\^=|::|->|//|[-+*/%^#<>=(){}\[\];:,.?|&])
''', re.X)


def tokenize(src, fname):
    toks = []
    i = 0
    line = 1
    n = len(src)
    while i < n:
        c = src[i]
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '\n':
                    raise LuauError(f'{fname}:{line}: unterminated string')
                j += 1
            if j >= n:
                raise LuauError(f'{fname}:{line}: unterminated string')
            toks.append(('str', src[i:j + 1], line))
            i = j + 1
            continue
        if c == '`':
            j = i + 1
            depth = 0
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '{':
                    depth += 1
                elif src[j] == '}':
                    depth -= 1
                elif src[j] == '`' and depth == 0:
                    break
                elif src[j] == '\n':
                    line += 1
                j += 1
            toks.append(('str', src[i:j + 1], line))
            i = j + 1
            continue
        if c == '[' and re.match(r'\[=*\[', src[i:]):
            m = re.match(r'\[(=*)\[', src[i:])
            close = ']' + m.group(1) + ']'
            j = src.find(close, i)
            if j < 0:
                raise LuauError(f'{fname}:{line}: unterminated long string')
            line += src.count('\n', i, j)
            toks.append(('str', 'longstring', line))
            i = j + len(close)
            continue
        m = TOKEN_RE.match(src, i)
        if not m:
            raise LuauError(f'{fname}:{line}: unexpected character {c!r}')
        kind = m.lastgroup
        text = m.group(kind)
        if kind == 'nl':
            line += 1
        elif kind == 'comment':
            rest = src[i + 2:]
            lm = re.match(r'\[(=*)\[', rest)
            if lm:
                close = ']' + lm.group(1) + ']'
                j = src.find(close, i)
                if j < 0:
                    raise LuauError(f'{fname}:{line}: unterminated long comment')
                line += src.count('\n', i, j)
                i = j + len(close)
                continue
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        elif kind == 'ws':
            pass
        elif kind == 'name':
            toks.append(('kw' if text in KEYWORDS else 'name', text, line))
        elif kind == 'num':
            toks.append(('num', text, line))
        else:
            toks.append(('op', text, line))
        i = m.end()
    toks.append(('eof', '<eof>', line))
    return toks


BINPRI = {
    'or': (1, 1), 'and': (2, 2),
    '<': (3, 3), '>': (3, 3), '<=': (3, 3), '>=': (3, 3), '~=': (3, 3), '==': (3, 3),
    '..': (5, 4), '+': (6, 6), '-': (6, 6),
    '*': (7, 7), '/': (7, 7), '//': (7, 7), '%': (7, 7),
    '^': (10, 9),
}
UNARY_PRI = 8


class Scope:
    def __init__(self, parent=None, func=False):
        self.parent = parent
        self.names = set()
        self.func = func

    def has(self, name):
        s = self
        while s:
            if name in s.names:
                return True
            s = s.parent
        return False


class Parser:
    def __init__(self, toks, fname):
        self.t = toks
        self.p = 0
        self.f = fname
        self.errors = []
        self.scope = Scope(func=True)
        self.loop_depth = [0]

    # helpers
    def peek(self, k=0):
        return self.t[self.p + k]

    def check(self, text, kind=None):
        tk = self.t[self.p]
        if kind and tk[0] != kind:
            return False
        return tk[1] == text and tk[0] in ('op', 'kw')

    def accept(self, text):
        if self.check(text):
            self.p += 1
            return True
        return False

    def expect(self, text, ctx=''):
        if not self.accept(text):
            tk = self.peek()
            raise LuauError(f'{self.f}:{tk[2]}: expected {text!r} {ctx} near {tk[1]!r}')

    def name(self):
        tk = self.peek()
        if tk[0] != 'name':
            raise LuauError(f'{self.f}:{tk[2]}: expected name near {tk[1]!r}')
        self.p += 1
        return tk[1], tk[2]

    def err(self, msg, line):
        self.errors.append(f'{self.f}:{line}: {msg}')

    def push(self, func=False):
        self.scope = Scope(self.scope, func)

    def pop(self):
        self.scope = self.scope.parent

    def declare(self, name):
        self.scope.names.add(name)

    def use(self, name, line, write=False):
        if self.scope.has(name) or name in GLOBALS:
            return
        if write:
            self.err(f'assignment to undeclared global {name!r}', line)
        else:
            self.err(f'undefined global {name!r}', line)

    # types (skipped loosely)
    def skip_type(self):
        depth = 0
        while True:
            tk = self.peek()
            if tk[0] == 'eof':
                return
            if tk[1] in ('(', '{', '<') and tk[0] == 'op':
                depth += 1
            elif tk[1] in (')', '}', '>') and tk[0] == 'op':
                if depth == 0:
                    return
                depth -= 1
            elif depth == 0 and (tk[1] in (',', '=', ';') or tk[0] == 'kw' and tk[1] not in ('nil', 'function')):
                return
            elif depth == 0 and tk[0] == 'op' and tk[1] == ')':
                return
            self.p += 1
            if depth == 0:
                nxt = self.peek()
                # continue only for type operators
                if nxt[0] == 'op' and nxt[1] in ('|', '&', '?', '.', '->'):
                    if nxt[1] == '?':
                        self.p += 1
                        nxt = self.peek()
                        if not (nxt[0] == 'op' and nxt[1] in ('|', '&')):
                            return
                    continue
                if nxt[0] == 'op' and nxt[1] in ('(', '{', '<'):
                    continue
                return

    # grammar
    def chunk(self):
        self.block()
        if self.peek()[0] != 'eof':
            tk = self.peek()
            raise LuauError(f'{self.f}:{tk[2]}: unexpected {tk[1]!r}')

    def block_end(self):
        tk = self.peek()
        return tk[0] == 'eof' or (tk[0] == 'kw' and tk[1] in ('end', 'else', 'elseif', 'until'))

    def block(self):
        while not self.block_end():
            if self.check('return'):
                self.p += 1
                if not self.block_end() and not self.check(';'):
                    self.exprlist()
                self.accept(';')
                if not self.block_end():
                    tk = self.peek()
                    raise LuauError(f'{self.f}:{tk[2]}: code after return near {tk[1]!r}')
                return
            self.statement()

    def statement(self):
        tk = self.peek()
        line = tk[2]
        if self.accept(';'):
            return
        if tk[0] == 'kw':
            w = tk[1]
            if w == 'if':
                self.p += 1
                self.expr()
                self.expect('then', 'in if')
                self.push(); self.block(); self.pop()
                while self.accept('elseif'):
                    self.expr()
                    self.expect('then', 'in elseif')
                    self.push(); self.block(); self.pop()
                if self.accept('else'):
                    self.push(); self.block(); self.pop()
                self.expect('end', f'to close if at line {line}')
                return
            if w == 'while':
                self.p += 1
                self.expr()
                self.expect('do')
                self.loop(lambda: self.block())
                self.expect('end', f'to close while at line {line}')
                return
            if w == 'do':
                self.p += 1
                self.push(); self.block(); self.pop()
                self.expect('end', f'to close do at line {line}')
                return
            if w == 'for':
                self.p += 1
                n1, l1 = self.name()
                if self.accept(':'):
                    self.skip_type()
                names = [n1]
                if self.accept('='):
                    self.expr(); self.expect(',')
                    self.expr()
                    if self.accept(','):
                        self.expr()
                else:
                    while self.accept(','):
                        names.append(self.name()[0])
                        if self.accept(':'):
                            self.skip_type()
                    self.expect('in')
                    self.exprlist()
                self.expect('do')
                self.push()
                for nm in names:
                    self.declare(nm)
                self.loop(lambda: self.block())
                self.pop()
                self.expect('end', f'to close for at line {line}')
                return
            if w == 'repeat':
                self.p += 1
                self.loop_depth[-1] += 1
                self.push()
                self.block()
                self.loop_depth[-1] -= 1
                self.expect('until')
                self.expr()
                self.pop()
                return
            if w == 'function':
                self.p += 1
                n, nl = self.name()
                self.use(n, nl)
                is_method = False
                while self.check('.') or self.check(':'):
                    if self.accept(':'):
                        self.name(); is_method = True
                        break
                    self.p += 1
                    self.name()
                self.funcbody(is_method)
                return
            if w == 'local':
                self.p += 1
                if self.accept('function'):
                    n, _ = self.name()
                    self.declare(n)
                    self.funcbody(False)
                    return
                names = []
                while True:
                    n, _ = self.name()
                    names.append(n)
                    if self.accept(':'):
                        self.skip_type()
                    if not self.accept(','):
                        break
                if self.accept('='):
                    self.exprlist()
                for n in names:
                    self.declare(n)
                return
            if w == 'break' or w == 'continue':
                self.p += 1
                if self.loop_depth[-1] == 0:
                    self.err(f'{w} outside loop', line)
                return
            if w == 'return':
                raise LuauError(f'{self.f}:{line}: unexpected return')
        # type declarations
        if tk[0] == 'name' and tk[1] in ('type', 'export') and self.peek(1)[0] == 'name':
            if tk[1] == 'export':
                self.p += 1
            self.p += 1
            self.name()
            if self.accept('<'):
                while not self.accept('>'):
                    self.p += 1
            self.expect('=')
            self.skip_type()
            return
        # exprstat
        targets = [self.suffixedexp(stmt=True)]
        if self.check('=') or self.check(','):
            while self.accept(','):
                targets.append(self.suffixedexp(stmt=True))
            self.expect('=')
            for kind, nm, nl in targets:
                if kind == 'call':
                    raise LuauError(f'{self.f}:{nl}: cannot assign to call')
                if kind == 'name':
                    self.use(nm, nl, write=True)
            self.exprlist()
            return
        tk2 = self.peek()
        if tk2[0] == 'op' and tk2[1] in ('+=', '-=', '*=', '/=', '//=', '%=', '^=', '..='):
            self.p += 1
            kind, nm, nl = targets[0]
            if kind == 'call':
                raise LuauError(f'{self.f}:{nl}: cannot assign to call')
            if kind == 'name':
                self.use(nm, nl)
            self.expr()
            return
        kind, nm, nl = targets[0]
        if kind != 'call':
            raise LuauError(f'{self.f}:{nl}: syntax error: expression is not a statement near {self.peek()[1]!r}')

    def loop(self, fn):
        self.loop_depth[-1] += 1
        self.push()
        fn()
        self.pop()
        self.loop_depth[-1] -= 1

    def funcbody(self, is_method):
        line = self.peek()[2]
        if self.check('<'):
            while not self.accept('>'):
                self.p += 1
        self.expect('(')
        self.push(func=True)
        self.loop_depth.append(0)
        if is_method:
            self.declare('self')
        if not self.check(')'):
            while True:
                if self.accept('...'):
                    self.declare('...')
                    if self.accept(':'):
                        self.skip_type()
                    break
                n, _ = self.name()
                self.declare(n)
                if self.accept(':'):
                    self.skip_type()
                if not self.accept(','):
                    break
        self.expect(')')
        if self.accept(':'):
            self.skip_type()
        self.block()
        self.expect('end', f'to close function at line {line}')
        self.loop_depth.pop()
        self.pop()

    def exprlist(self):
        self.expr()
        while self.accept(','):
            self.expr()

    def primaryexp(self):
        tk = self.peek()
        if tk[0] == 'name':
            self.p += 1
            self.use(tk[1], tk[2]) if not self.assign_ctx else None
            return ('name', tk[1], tk[2])
        if self.accept('('):
            self.expr()
            self.expect(')')
            return ('paren', None, tk[2])
        raise LuauError(f'{self.f}:{tk[2]}: unexpected symbol near {tk[1]!r}')

    assign_ctx = False

    def suffixedexp(self, stmt=False):
        tk = self.peek()
        start = self.p
        # defer global check for possible assignment target
        if stmt and tk[0] == 'name':
            self.p += 1
            kind, nm, nl = 'name', tk[1], tk[2]
            first_is_name = True
        else:
            kind, nm, nl = self.primaryexp()
            first_is_name = False
        base_name = nm if kind == 'name' else None
        used = not first_is_name
        while True:
            t = self.peek()
            if t[0] == 'op' and t[1] == '.':
                if not used:
                    self.use(base_name, nl); used = True
                self.p += 1
                mem, ml = self.name()
                if kind == 'name' and base_name in LIBS and not self.scope.has(base_name):
                    if mem not in LIBS[base_name]:
                        self.err(f'unknown member {base_name}.{mem}', ml)
                kind, nm = 'index', mem
            elif t[0] == 'op' and t[1] == '[':
                if not used:
                    self.use(base_name, nl); used = True
                self.p += 1
                self.expr()
                self.expect(']')
                kind = 'index'
            elif t[0] == 'op' and t[1] == ':':
                if not used:
                    self.use(base_name, nl); used = True
                self.p += 1
                self.name()
                self.callargs()
                kind = 'call'
            elif (t[0] == 'op' and t[1] in ('(', '{')) or t[0] == 'str':
                if not used:
                    self.use(base_name, nl); used = True
                if t[0] == 'op' and t[1] == '(' and t[2] != self.t[self.p - 1][2]:
                    self.err('ambiguous syntax: call on new line', t[2])
                self.callargs()
                kind = 'call'
            elif t[0] == 'op' and t[1] == '::':
                self.p += 1
                self.skip_type()
            else:
                break
        if not used:
            # bare name: assignment target or read decided by caller
            nxt = self.peek()
            if not (nxt[0] == 'op' and nxt[1] in ('=', ',')):
                self.use(base_name, nl)
        return (kind, nm, nl)

    def callargs(self):
        t = self.peek()
        if t[0] == 'str':
            self.p += 1
            return
        if self.check('{'):
            self.table()
            return
        self.expect('(')
        if not self.check(')'):
            self.exprlist()
        self.expect(')', 'to close call')

    def table(self):
        self.expect('{')
        while not self.check('}'):
            if self.accept('['):
                self.expr()
                self.expect(']')
                self.expect('=')
                self.expr()
            elif self.peek()[0] == 'name' and self.peek(1)[1] == '=' and self.peek(1)[0] == 'op':
                self.p += 2
                self.expr()
            else:
                self.expr()
            if not (self.accept(',') or self.accept(';')):
                break
        self.expect('}', 'to close table')

    def simpleexp(self):
        tk = self.peek()
        if tk[0] in ('num', 'str'):
            self.p += 1
            return
        if tk[0] == 'kw' and tk[1] in ('nil', 'true', 'false'):
            self.p += 1
            return
        if self.accept('...'):
            if not self.scope_has_vararg():
                self.err('vararg used outside vararg function', tk[2])
            return
        if self.check('{'):
            self.table()
            return
        if self.accept('function'):
            self.funcbody(False)
            return
        if self.check('if'):
            self.p += 1
            self.expr(); self.expect('then'); self.expr()
            while self.accept('elseif'):
                self.expr(); self.expect('then'); self.expr()
            self.expect('else', 'in if-expression')
            self.expr()
            return
        self.suffixedexp()

    def scope_has_vararg(self):
        s = self.scope
        while s:
            if '...' in s.names:
                return True
            if s.func and s.parent is None:
                return True  # main chunk is vararg
            if s.func:
                return False
            s = s.parent
        return True

    def expr(self, limit=0):
        tk = self.peek()
        if (tk[0] == 'kw' and tk[1] == 'not') or (tk[0] == 'op' and tk[1] in ('-', '#')):
            self.p += 1
            self.expr(UNARY_PRI)
        else:
            self.simpleexp()
        while True:
            t = self.peek()
            op = t[1] if t[0] in ('op', 'kw') else None
            if op in BINPRI and BINPRI[op][0] > limit:
                self.p += 1
                self.expr(BINPRI[op][1])
            else:
                break


def check_file(path):
    src = open(path, encoding='utf-8').read()
    try:
        toks = tokenize(src, path)
        p = Parser(toks, path)
        p.chunk()
        return p.errors
    except LuauError as e:
        return [str(e)]


def main(argv):
    files = []
    for a in argv:
        if os.path.isdir(a):
            for root, _, fs in os.walk(a):
                for f in fs:
                    if f.endswith('.luau') or f.endswith('.lua'):
                        files.append(os.path.join(root, f))
        else:
            files.append(a)
    total = 0
    for f in sorted(files):
        errs = check_file(f)
        for e in errs:
            print(e)
        total += len(errs)
    print(f'checked {len(files)} files, {total} problem(s)')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
