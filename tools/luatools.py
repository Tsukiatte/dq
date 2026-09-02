"""Static helpers for Lua sources: real parse (lupa) and scope-aware free-name analysis (luaparser)."""
import re
from luaparser import ast, astnodes as N

_lua = None


def lua_parse_error(src, chunkname="chunk"):
    """Returns None if `src` parses under real Lua 5.x, else the error string."""
    global _lua
    if _lua is None:
        from lupa import LuaRuntime
        _lua = LuaRuntime()
        _lua.execute(
            "function __check(src, name) local f, e = load(src, name, 't') "
            "if f then return nil end return e end"
        )
    err = _lua.globals()["__check"](src, "=" + chunkname)
    return None if err is None else str(err)


def _children(node):
    for key, val in vars(node).items():
        if key.startswith("_") or key in ("comments",):
            continue
        if isinstance(val, N.Node):
            yield key, val
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, N.Node):
                    yield key, item


class Scope:
    def __init__(self, parent=None):
        self.parent = parent
        self.names = set()

    def declare(self, name):
        self.names.add(name)

    def resolves(self, name):
        s = self
        while s:
            if name in s.names:
                return True
            s = s.parent
        return False


def free_names(src):
    """Returns {name: first_line} of every identifier referenced (read or assigned) that is not a local."""
    tree = ast.parse(src)
    free = {}

    def ref(node, scope):
        if not isinstance(node, N.Node):
            return
        if isinstance(node, N.Name):
            if not scope.resolves(node.id):
                line = getattr(node, "line", None) or 0
                free.setdefault(node.id, line)
        else:
            visit(node, scope)

    def visit_block(block, scope):
        inner = Scope(scope)
        for stmt in block.body:
            visit(stmt, inner)
        return inner

    def visit_function(args, body, scope, extra=()):
        fscope = Scope(scope)
        for name in extra:
            fscope.declare(name)
        for a in args:
            if isinstance(a, N.Name):
                fscope.declare(a.id)
        visit_block(body, fscope)

    def visit(node, scope):
        if isinstance(node, N.Chunk):
            visit_block(node.body, scope)
        elif isinstance(node, N.Block):
            visit_block(node, scope)
        elif isinstance(node, N.LocalAssign):
            for v in node.values or []:
                ref(v, scope)
            for t in node.targets:
                if isinstance(t, N.Name):
                    scope.declare(t.id)
        elif isinstance(node, N.LocalFunction):
            scope.declare(node.name.id)
            visit_function(node.args, node.body, scope)
        elif isinstance(node, N.Function):
            ref(node.name, scope)
            visit_function(node.args, node.body, scope)
        elif isinstance(node, N.Method):
            ref(node.source, scope)
            visit_function(node.args, node.body, scope, extra=("self",))
        elif isinstance(node, N.AnonymousFunction):
            visit_function(node.args, node.body, scope)
        elif isinstance(node, N.Fornum):
            for v in (node.start, node.stop, node.step):
                if v is not None:
                    ref(v, scope)
            fscope = Scope(scope)
            fscope.declare(node.target.id)
            visit_block(node.body, fscope)
        elif isinstance(node, N.Forin):
            for v in node.iter if isinstance(node.iter, list) else [node.iter]:
                ref(v, scope)
            fscope = Scope(scope)
            for t in node.targets:
                fscope.declare(t.id)
            visit_block(node.body, fscope)
        elif isinstance(node, N.Repeat):
            inner = visit_block(node.body, scope)
            ref(node.test, inner)
        elif isinstance(node, N.While):
            ref(node.test, scope)
            visit_block(node.body, scope)
        elif isinstance(node, N.If):
            ref(node.test, scope)
            visit_block(node.body, scope)
            orelse = node.orelse
            if isinstance(orelse, N.ElseIf):
                visit(orelse, scope)
            elif isinstance(orelse, N.Block):
                visit_block(orelse, scope)
            elif orelse is not None:
                visit(orelse, scope)
        elif isinstance(node, N.ElseIf):
            ref(node.test, scope)
            visit_block(node.body, scope)
            orelse = node.orelse
            if isinstance(orelse, N.ElseIf):
                visit(orelse, scope)
            elif isinstance(orelse, N.Block):
                visit_block(orelse, scope)
            elif orelse is not None:
                visit(orelse, scope)
        elif isinstance(node, N.Do):
            visit_block(node.body, scope)
        elif isinstance(node, N.Assign):
            for v in node.values:
                ref(v, scope)
            for t in node.targets:
                ref(t, scope)
        elif isinstance(node, N.Index):
            ref(node.value, scope)
            if node.notation == N.IndexNotation.DOT:
                pass  # field name, not a reference
            else:
                ref(node.idx, scope)
        elif isinstance(node, N.Invoke):
            ref(node.source, scope)
            for a in node.args:
                ref(a, scope)
        elif isinstance(node, N.Call):
            ref(node.func, scope)
            for a in node.args:
                ref(a, scope)
        elif isinstance(node, N.Table):
            for f in node.fields:
                if f.between_brackets or not isinstance(f.key, N.Name):
                    ref(f.key, scope)
                ref(f.value, scope)
        elif isinstance(node, N.Field):
            if node.between_brackets or not isinstance(node.key, N.Name):
                ref(node.key, scope)
            ref(node.value, scope)
        elif isinstance(node, N.Return):
            for v in node.values:
                ref(v, scope)
        elif isinstance(node, N.Name):
            ref(node, scope)
        else:
            for _, child in _children(node):
                ref(child, scope)

    visit(tree, Scope())
    return free


# Names Roblox / Luau / the executor provide. Anything free and not in here is a bug.
KNOWN_GLOBALS = set("""
game workspace script Instance Vector2 Vector3 CFrame Color3 UDim UDim2 Enum RaycastParams
Rect Region3 NumberRange NumberSequence ColorSequence TweenInfo BrickColor Random
task wait spawn delay tick time os math string table coroutine utf8 bit32 debug
print warn error assert pcall xpcall ipairs pairs next select type typeof tostring tonumber
unpack rawget rawset rawequal rawlen setmetatable getmetatable require _G _VERSION
loadstring getgenv getrawmetatable setreadonly newcclosure getnamecallmethod checkcaller
writefile readfile isfile makefolder isfolder delfile listfiles
""".split())


def strip_strings_and_comments(raw):
    """Same scanner luacheck.py used: returns source with comments removed and string bodies replaced by STR."""
    out = []
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if raw.startswith("--[[", i):
            j = raw.find("]]", i)
            j = n if j == -1 else j + 2
            out.append("\n" * raw.count("\n", i, j))
            i = j
        elif raw.startswith("--", i):
            j = raw.find("\n", i)
            j = n if j == -1 else j
            i = j
        elif c == '"' or c == "'":
            q = c
            i += 1
            while i < n and raw[i] != q:
                if raw[i] == "\\":
                    i += 1
                i += 1
            i += 1
            out.append("STR")
        else:
            out.append(c)
            i += 1
    return "".join(out)
