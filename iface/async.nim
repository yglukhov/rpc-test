import asyncdispatch, macros
# or import chronos

import ../iface

template wrapTypeIntoFuture(T: typedesc): untyped =
  when T is Future:
    T
  else:
    Future[T]

macro deriveAsyncInterface(name: untyped, fromInterface: typedesc): untyped =
  let decl = copyNimTree(getInterfaceDecl(fromInterface))
  let newDecl = newNimNode(nnkStmtList)
  for i, p in decl:
    var retType = p.params[0]
    if retType.kind == nnkEmpty:
      retType = ident"void"
    # ap.params[0] = newCall(bindSym"wrapTypeIntoFuture", retType)
    newDecl.add(p)

  result = ifaceImpl(ident"Blabla", newDecl)
  # echo "DERRRIVE ASYNC: ", repr(result)

# type
  # AsyncVTable[TVT, Inter] = asyncify(TVT, Inter)
  # Async*[Inter] = Interface[asyncify(Inter)]

iface Foo:
    proc p1(): int
    proc p2()

type Bar = ref object
proc p1(b: Bar): Future[int] {.async.} = return 5
proc p2(b: Bar) = discard

# iface AsyncFoo:
#   proc p1(): Future[int]
#   proc p2(): Future[void]
deriveAsyncInterface(AsyncFoo, Foo)

# let a = to(Bar(), asyncify(Foo))
# type
#   AsyncFoo = Async[Foo]
