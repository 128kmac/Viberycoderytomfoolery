#!/usr/bin/env python3
"""Luau -> Lua 5.4 source translator used by the headless test harness.

Handles the Luau features this project can contain:
  compound assignment (+= -= *= /= //= %= ^= ..=), `continue`, if-expressions,
  interpolated `strings {x}`, type annotations / casts / type declarations,
  numeric literals with `_` separators and 0b prefixes.
Output keeps statement line numbers aligned with the source so runtime errors
point at the right Luau line.
"""
import re
import sys

KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in',
    'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while', 'continue',
}

TOKEN_RE = re.compile(r'''
    (?P<ws>[ \t\r]+) |
    (?P<nl>\n) |
    (?P<comment>--) |
    (?P<num>0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<op>\.\.\.|\.\.=|//=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|%=|\^=|::|->|//|[-+*/%^#<>=(){}\[\];:,.?|&])
''', re.X)


class TranspileError(Exception):
    pass


def tokenize(src, fname):
    toks = []
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    if src[j + 1:j + 2] == 'z':
                        j += 2
                        while j < n and src[j] in ' \t\r\n':
                            j += 1
                        continue
                    j += 2
                    continue
                if src[j] == '\n':
                    raise TranspileError(f'{fname}:{line}: unterminated string')
                j += 1
            toks.append(('str', src[i:j + 1], line))
            line += src.count('\n', i, j + 1)
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
                j += 1
            toks.append(('interp', src[i + 1:j], line))
            line += src.count('\n', i, j)
            i = j + 1
            continue
        if c == '[':
            m = re.match(r'\[(=*)\[', src[i:])
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, i)
                if j < 0:
                    raise TranspileError(f'{fname}:{line}: unterminated long string')
                toks.append(('str', src[i:j + len(close)], line))
                line += src.count('\n', i, j)
                i = j + len(close)
                continue
        m = TOKEN_RE.match(src, i)
        if not m:
            raise TranspileError(f'{fname}:{line}: unexpected character {c!r}')
        kind = m.lastgroup
        text = m.group(kind)
        if kind == 'nl':
            line += 1
        elif kind == 'comment':
            lm = re.match(r'\[(=*)\[', src[i + 2:])
            if lm:
                close = ']' + lm.group(1) + ']'
                j = src.find(close, i)
                if j < 0:
                    raise TranspileError(f'{fname}:{line}: unterminated long comment')
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
COMPOUND = {'+=': '+', '-=': '-', '*=': '*', '/=': '/', '//=': '//', '%=': '%', '^=': '^', '..=': '..'}


class Parser:
    """Builds a small AST: tuples (kind, line, ...)."""

    def __init__(self, toks, fname):
        self.t = toks
        self.p = 0
        self.f = fname

    def peek(self, k=0):
        return self.t[self.p + k]

    def check(self, text):
        tk = self.t[self.p]
        return tk[1] == text and tk[0] in ('op', 'kw')

    def accept(self, text):
        if self.check(text):
            self.p += 1
            return True
        return False

    def expect(self, text, ctx=''):
        if not self.accept(text):
            tk = self.peek()
            raise TranspileError(f'{self.f}:{tk[2]}: expected {text!r} {ctx} near {tk[1]!r}')

    def name(self):
        tk = self.peek()
        if tk[0] != 'name':
            raise TranspileError(f'{self.f}:{tk[2]}: expected name near {tk[1]!r}')
        self.p += 1
        return tk[1]

    # types are parsed loosely and discarded
    def skip_type(self):
        depth = 0
        while True:
            tk = self.peek()
            if tk[0] == 'eof':
                return
            if tk[0] == 'op' and tk[1] in ('(', '{', '<'):
                depth += 1
            elif tk[0] == 'op' and tk[1] in (')', '}', '>'):
                if depth == 0:
                    return
                depth -= 1
            elif depth == 0 and (tk[1] in (',', '=', ';') or (tk[0] == 'kw' and tk[1] not in ('nil', 'function'))):
                return
            self.p += 1
            if depth == 0:
                nxt = self.peek()
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

    def chunk(self):
        b = self.block()
        if self.peek()[0] != 'eof':
            tk = self.peek()
            raise TranspileError(f'{self.f}:{tk[2]}: unexpected {tk[1]!r}')
        return b

    def block_end(self):
        tk = self.peek()
        return tk[0] == 'eof' or (tk[0] == 'kw' and tk[1] in ('end', 'else', 'elseif', 'until'))

    def block(self):
        stmts = []
        while not self.block_end():
            if self.check('return'):
                line = self.peek()[2]
                self.p += 1
                exprs = []
                if not self.block_end() and not self.check(';'):
                    exprs = self.exprlist()
                self.accept(';')
                stmts.append(('return', line, exprs))
                break
            s = self.statement()
            if s is not None:
                stmts.append(s)
        return stmts

    def statement(self):
        tk = self.peek()
        line = tk[2]
        if self.accept(';'):
            return None
        if tk[0] == 'kw':
            w = tk[1]
            if w == 'if':
                self.p += 1
                clauses = []
                cond = self.expr()
                self.expect('then')
                clauses.append((cond, self.block()))
                els = None
                while True:
                    if self.accept('elseif'):
                        cond = self.expr()
                        self.expect('then')
                        clauses.append((cond, self.block()))
                    elif self.accept('else'):
                        els = self.block()
                        self.expect('end', f'to close if at line {line}')
                        break
                    else:
                        self.expect('end', f'to close if at line {line}')
                        break
                return ('if', line, clauses, els)
            if w == 'while':
                self.p += 1
                cond = self.expr()
                self.expect('do')
                body = self.block()
                self.expect('end')
                return ('while', line, cond, body)
            if w == 'do':
                self.p += 1
                body = self.block()
                self.expect('end')
                return ('do', line, body)
            if w == 'for':
                self.p += 1
                n1 = self.name()
                if self.accept(':'):
                    self.skip_type()
                if self.accept('='):
                    a = self.expr()
                    self.expect(',')
                    b = self.expr()
                    c = self.expr() if self.accept(',') else None
                    self.expect('do')
                    body = self.block()
                    self.expect('end')
                    return ('numfor', line, n1, a, b, c, body)
                names = [n1]
                while self.accept(','):
                    names.append(self.name())
                    if self.accept(':'):
                        self.skip_type()
                self.expect('in')
                exprs = self.exprlist()
                self.expect('do')
                body = self.block()
                self.expect('end')
                return ('genfor', line, names, exprs, body)
            if w == 'repeat':
                self.p += 1
                body = self.block()
                self.expect('until')
                cond = self.expr()
                return ('repeat', line, body, cond)
            if w == 'function':
                self.p += 1
                parts = [self.name()]
                method = None
                while True:
                    if self.accept('.'):
                        parts.append(self.name())
                    elif self.accept(':'):
                        method = self.name()
                        break
                    else:
                        break
                fn = self.funcbody(method is not None)
                return ('funcstat', line, parts, method, fn)
            if w == 'local':
                self.p += 1
                if self.accept('function'):
                    nm = self.name()
                    fn = self.funcbody(False)
                    return ('localfunc', line, nm, fn)
                names = []
                attribs = []
                while True:
                    names.append(self.name())
                    if self.accept('<'):  # Lua attribs (unused in Luau) - tolerate
                        attribs.append(self.name())
                        self.expect('>')
                    if self.accept(':'):
                        self.skip_type()
                    if not self.accept(','):
                        break
                exprs = self.exprlist() if self.accept('=') else []
                return ('local', line, names, exprs)
            if w == 'break':
                self.p += 1
                return ('break', line)
            if w == 'continue':
                self.p += 1
                return ('continue', line)
        if tk[0] == 'name' and tk[1] in ('type', 'export') and self.peek(1)[0] == 'name':
            if tk[1] == 'export':
                self.p += 1
            self.p += 1
            self.name()
            if self.accept('<'):
                depth = 1
                while depth:
                    t = self.peek()
                    self.p += 1
                    if t[1] == '<':
                        depth += 1
                    elif t[1] == '>':
                        depth -= 1
            self.expect('=')
            self.skip_type()
            return None
        target = self.suffixedexp()
        if self.check('=') or self.check(','):
            targets = [target]
            while self.accept(','):
                targets.append(self.suffixedexp())
            self.expect('=')
            exprs = self.exprlist()
            return ('assign', line, targets, exprs)
        tk2 = self.peek()
        if tk2[0] == 'op' and tk2[1] in COMPOUND:
            self.p += 1
            e = self.expr()
            return ('compound', line, target, COMPOUND[tk2[1]], e)
        if target[0] not in ('call', 'mcall'):
            raise TranspileError(f'{self.f}:{line}: syntax error near {self.peek()[1]!r}')
        return ('callstat', line, target)

    def funcbody(self, is_method):
        line = self.peek()[2]
        if self.check('<'):
            while not self.accept('>'):
                self.p += 1
        self.expect('(')
        params = []
        vararg = False
        if is_method:
            params.append('self')
        if not self.check(')'):
            while True:
                if self.accept('...'):
                    vararg = True
                    if self.accept(':'):
                        self.skip_type()
                    break
                params.append(self.name())
                if self.accept(':'):
                    self.skip_type()
                if not self.accept(','):
                    break
        self.expect(')')
        if self.accept(':'):
            self.skip_type()
        body = self.block()
        endline = self.peek()[2]
        self.expect('end', f'to close function at line {line}')
        return ('function', line, params, vararg, body, endline)

    def exprlist(self):
        out = [self.expr()]
        while self.accept(','):
            out.append(self.expr())
        return out

    def primaryexp(self):
        tk = self.peek()
        if tk[0] == 'name':
            self.p += 1
            return ('name', tk[2], tk[1])
        if self.accept('('):
            e = self.expr()
            self.expect(')')
            return ('paren', tk[2], e)
        raise TranspileError(f'{self.f}:{tk[2]}: unexpected symbol near {tk[1]!r}')

    def suffixedexp(self):
        e = self.primaryexp()
        while True:
            t = self.peek()
            if t[0] == 'op' and t[1] == '.':
                self.p += 1
                e = ('field', t[2], e, self.name())
            elif t[0] == 'op' and t[1] == '[':
                self.p += 1
                k = self.expr()
                self.expect(']')
                e = ('index', t[2], e, k)
            elif t[0] == 'op' and t[1] == ':' and self.peek(1)[0] == 'name' and not (self.peek(2)[0] == 'op' and self.peek(2)[1] == '='):
                # method call (a type annotation never follows an expression statement)
                self.p += 1
                nm = self.name()
                e = ('mcall', t[2], e, nm, self.callargs())
            elif (t[0] == 'op' and t[1] in ('(', '{')) or t[0] in ('str', 'interp'):
                e = ('call', t[2], e, self.callargs())
            elif t[0] == 'op' and t[1] == '::':
                self.p += 1
                self.skip_type()
            else:
                return e

    def callargs(self):
        t = self.peek()
        if t[0] == 'str':
            self.p += 1
            return [('str', t[2], t[1])]
        if t[0] == 'interp':
            self.p += 1
            return [self.interp(t)]
        if self.check('{'):
            return [self.table()]
        self.expect('(')
        args = []
        if not self.check(')'):
            args = self.exprlist()
        self.expect(')')
        return args

    def table(self):
        line = self.peek()[2]
        self.expect('{')
        items = []
        while not self.check('}'):
            if self.accept('['):
                k = self.expr()
                self.expect(']')
                self.expect('=')
                items.append(('kv', k, self.expr()))
            elif self.peek()[0] == 'name' and self.peek(1)[0] == 'op' and self.peek(1)[1] == '=':
                nm = self.name()
                self.p += 1
                items.append(('nv', nm, self.expr()))
            else:
                items.append(('v', self.expr()))
            if not (self.accept(',') or self.accept(';')):
                break
        self.expect('}')
        return ('table', line, items)

    def interp(self, tok):
        body, line = tok[1], tok[2]
        parts = []
        lit = []
        i = 0
        while i < len(body):
            ch = body[i]
            if ch == '\\' and i + 1 < len(body):
                nxt = body[i + 1]
                if nxt in '{}`':
                    lit.append(nxt)
                else:
                    lit.append(ch + nxt)
                i += 2
                continue
            if ch == '{':
                depth, j = 1, i + 1
                while j < len(body) and depth:
                    if body[j] == '{':
                        depth += 1
                    elif body[j] == '}':
                        depth -= 1
                    j += 1
                if lit:
                    parts.append(('lit', ''.join(lit)))
                    lit = []
                sub = Parser(tokenize(body[i + 1:j - 1], self.f), self.f)
                parts.append(('expr', sub.expr()))
                i = j
                continue
            lit.append(ch)
            i += 1
        if lit:
            parts.append(('lit', ''.join(lit)))
        return ('interp', line, parts)

    def simpleexp(self):
        tk = self.peek()
        if tk[0] == 'num':
            self.p += 1
            return ('num', tk[2], tk[1])
        if tk[0] == 'str':
            self.p += 1
            return ('str', tk[2], tk[1])
        if tk[0] == 'interp':
            self.p += 1
            return self.interp(tk)
        if tk[0] == 'kw' and tk[1] in ('nil', 'true', 'false'):
            self.p += 1
            return (tk[1], tk[2])
        if self.accept('...'):
            return ('vararg', tk[2])
        if self.check('{'):
            return self.table()
        if self.accept('function'):
            return self.funcbody(False)
        if self.check('if'):
            self.p += 1
            clauses = []
            c = self.expr()
            self.expect('then')
            clauses.append((c, self.expr()))
            while self.accept('elseif'):
                c = self.expr()
                self.expect('then')
                clauses.append((c, self.expr()))
            self.expect('else')
            return ('ifexpr', tk[2], clauses, self.expr())
        return self.suffixedexp()

    def expr(self, limit=0):
        tk = self.peek()
        if (tk[0] == 'kw' and tk[1] == 'not') or (tk[0] == 'op' and tk[1] in ('-', '#')):
            self.p += 1
            left = ('unop', tk[2], tk[1], self.expr(UNARY_PRI))
        else:
            left = self.simpleexp()
        while True:
            t = self.peek()
            op = t[1] if t[0] in ('op', 'kw') else None
            if op in BINPRI and BINPRI[op][0] > limit:
                self.p += 1
                right = self.expr(BINPRI[op][1])
                left = ('binop', t[2], op, left, right)
            elif t[0] == 'op' and t[1] == '::':
                self.p += 1
                self.skip_type()
            else:
                return left


def contains_continue(block):
    """True if `continue` appears in this loop body (not inside nested loops/functions)."""
    for s in block:
        k = s[0]
        if k == 'continue':
            return True
        if k == 'if':
            for _, b in s[2]:
                if contains_continue(b):
                    return True
            if s[3] and contains_continue(s[3]):
                return True
        elif k == 'do':
            if contains_continue(s[2]):
                return True
    return False


class Emitter:
    def __init__(self):
        self.out = []
        self.line = 1
        self.label_n = 0
        self.loop_labels = []
        self.tmp_n = 0

    def w(self, s):
        self.out.append(s)
        self.line += s.count('\n')

    def at(self, line):
        if line > self.line:
            self.w('\n' * (line - self.line))
        self.w(' ')

    def block(self, stmts):
        for s in stmts:
            self.stmt(s)

    def loop_body(self, body):
        if contains_continue(body):
            self.label_n += 1
            lab = f'__continue{self.label_n}'
            self.loop_labels.append(lab)
            self.w(' do ')
            self.block(body)
            self.w(f' end ::{lab}:: ')
            self.loop_labels.pop()
        else:
            self.loop_labels.append(None)
            self.block(body)
            self.loop_labels.pop()

    def stmt(self, s):
        k, line = s[0], s[1]
        self.at(line)
        if k == 'local':
            self.w('local ' + ', '.join(s[2]))
            if s[3]:
                self.w(' = ' + ', '.join(self.e(x) for x in s[3]))
        elif k == 'localfunc':
            self.w(f'local function {s[2]}')
            self.funcbody(s[3])
        elif k == 'funcstat':
            nm = '.'.join(s[2])
            if s[3]:
                nm += ':' + s[3]
                fn = s[4]
                fn = ('function', fn[1], fn[2][1:], fn[3], fn[4], fn[5])
                self.w(f'function {nm}')
                self.funcbody(fn)
            else:
                self.w(f'function {nm}')
                self.funcbody(s[4])
        elif k == 'assign':
            self.w(', '.join(self.e(t) for t in s[2]) + ' = ' + ', '.join(self.e(x) for x in s[3]))
        elif k == 'compound':
            target, op, val = s[2], s[3], s[4]
            v = self.e(val)
            if target[0] == 'name':
                self.w(f'{target[2]} = {target[2]} {op} ({v})')
            elif target[0] == 'field':
                obj = target[2]
                if obj[0] == 'name':
                    o = obj[2]
                    self.w(f'{o}.{target[3]} = {o}.{target[3]} {op} ({v})')
                else:
                    self.w(f'do local __t = {self.e(obj)}; __t.{target[3]} = __t.{target[3]} {op} ({v}) end')
            elif target[0] == 'index':
                self.w(f'do local __t, __k = {self.e(target[2])}, {self.e(target[3])}; __t[__k] = __t[__k] {op} ({v}) end')
            else:
                raise TranspileError(f'line {line}: bad compound assignment target')
        elif k == 'callstat':
            self.w(self.e(s[2]))
        elif k == 'do':
            self.w('do')
            self.block(s[2])
            self.w(' end')
        elif k == 'while':
            self.w(f'while {self.e(s[2])} do')
            self.loop_body(s[3])
            self.w(' end')
        elif k == 'repeat':
            if contains_continue(s[2]):
                raise TranspileError(f'line {line}: continue inside repeat-until is not supported by the harness')
            self.w('repeat')
            self.loop_labels.append(None)
            self.block(s[2])
            self.loop_labels.pop()
            self.w(f' until {self.e(s[3])}')
        elif k == 'if':
            for i, (cond, body) in enumerate(s[2]):
                self.w(('if ' if i == 0 else ' elseif ') + self.e(cond) + ' then')
                self.block(body)
            if s[3] is not None:
                self.w(' else')
                self.block(s[3])
            self.w(' end')
        elif k == 'numfor':
            rng = f'{self.e(s[3])}, {self.e(s[4])}' + (f', {self.e(s[5])}' if s[5] else '')
            self.w(f'for {s[2]} = {rng} do')
            self.loop_body(s[6])
            self.w(' end')
        elif k == 'genfor':
            self.w(f'for {", ".join(s[2])} in {", ".join(self.e(x) for x in s[3])} do')
            self.loop_body(s[4])
            self.w(' end')
        elif k == 'return':
            self.w('return ' + ', '.join(self.e(x) for x in s[2]))
        elif k == 'break':
            self.w('break')
        elif k == 'continue':
            lab = self.loop_labels[-1] if self.loop_labels else None
            if not lab:
                raise TranspileError(f'line {line}: continue outside a loop')
            self.w(f'goto {lab}')
        else:
            raise TranspileError(f'unknown statement {k}')
        self.w(';')

    def funcbody(self, fn):
        _, line, params, vararg, body, endline = fn
        ps = list(params) + (['...'] if vararg else [])
        self.w('(' + ', '.join(ps) + ')')
        saved = self.loop_labels
        self.loop_labels = []
        self.block(body)
        self.loop_labels = saved
        self.at(endline)
        self.w('end')

    def e(self, x):
        k = x[0]
        if k == 'name':
            return x[2]
        if k == 'num':
            t = x[2].replace('_', '')
            if t[:2].lower() == '0b':
                t = str(int(t[2:], 2))
            return t
        if k == 'str':
            return x[2]
        if k in ('nil', 'true', 'false'):
            return k
        if k == 'vararg':
            return '...'
        if k == 'paren':
            return '(' + self.e(x[2]) + ')'
        if k == 'field':
            return f'{self.e(x[2])}.{x[3]}'
        if k == 'index':
            return f'{self.e(x[2])}[{self.e(x[3])}]'
        if k == 'call':
            return f'{self.e(x[2])}({", ".join(self.e(a) for a in x[3])})'
        if k == 'mcall':
            return f'{self.e(x[2])}:{x[3]}({", ".join(self.e(a) for a in x[4])})'
        if k == 'unop':
            op = x[2]
            sep = ' ' if op == 'not' else ''
            return f'({op}{sep}{self.e(x[3])})'
        if k == 'binop':
            if x[2] == '..':
                # Luau prints integral floats without '.0'; route through a Luau-style concat
                return f'__cat({self.e(x[3])}, {self.e(x[4])})'
            return f'({self.e(x[3])} {x[2]} {self.e(x[4])})'
        if k == 'table':
            parts = []
            for it in x[2]:
                if it[0] == 'kv':
                    parts.append(f'[{self.e(it[1])}] = {self.e(it[2])}')
                elif it[0] == 'nv':
                    parts.append(f'{it[1]} = {self.e(it[2])}')
                else:
                    parts.append(self.e(it[1]))
            # keep multi-line tables on their lines for error locality
            return '{' + ', '.join(parts) + '}'
        if k == 'function':
            saved_out, saved_line = self.out, self.line
            self.out = []
            self.w('function')
            self.funcbody(x)
            s = ''.join(self.out)
            self.out = saved_out
            self.line = saved_line + s.count('\n')
            return s
        if k == 'ifexpr':
            clauses, els = x[2], x[3]
            res = f'{{({self.e(els)})}}'
            for cond, val in reversed(clauses):
                res = f'{{(({self.e(cond)}) and {{({self.e(val)})}} or {res})[1]}}'
            return f'({res[1:-1]})'
        if k == 'interp':
            segs = []
            for kind, v in x[2]:
                if kind == 'lit':
                    segs.append('"' + v.replace('"', '\\"').replace('\n', '\\n') + '"')
                else:
                    segs.append(f'tostring({self.e(v)})')
            return '(' + (' .. '.join(segs) if segs else '""') + ')'
        raise TranspileError(f'unknown expression {k}')


def transpile(src, fname='<luau>'):
    toks = tokenize(src, fname)
    ast = Parser(toks, fname).chunk()
    em = Emitter()
    em.block(ast)
    return ''.join(em.out)


if __name__ == '__main__':
    for path in sys.argv[1:]:
        sys.stdout.write(transpile(open(path, encoding='utf-8').read(), path))
