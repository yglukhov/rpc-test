import macros, tables

type
  Interface*[VTable] = object
    private_vTable*: ptr VTable
    private_obj*: RootRef

  CTWrapper[T] = ref object of RootRef
    v: T

proc getVTable(VTable: typedesc, T: typedesc): ptr VTable =
  mixin initVTable
  var tab {.global.} = initVTable(VTable, T)
  addr tab

template unpackObj[T](f: RootRef, res: var T) =
  when nimvm:
    res = CTWrapper[T](f).v
  else:
    res = cast[T](f)

proc packObj[T](v: T): RootRef {.inline.} =
  when nimvm:
    result = CTWrapper[T](v: v)
  else:
    result = cast[RootRef](v)

macro checkRequiredMethod(call: typed, typ: typed): untyped =
  let impl = getImpl(call[0])
  if impl.kind == nnkProcDef and impl.params.len > 1 and impl.params[1][^2] == typ:
    error "Object does not implement required interface method: " & repr(call)
  result = call

template forceReturnValue(retType: typed, someCall: typed): untyped =
  when retType is void:
    someCall
  else:
    return someCall

var interfaceDecls {.compileTime.} = initTable[string, NimNode]()
var constructorDecls {.compileTime.} = initTable[string, NimNode]()

proc getInterfaceKey(sym: NimNode): string =
  let t = getTypeImpl(sym)
  expectKind(t, nnkBracketExpr)
  assert(t.len == 2)
  assert t[0].eqIdent("typedesc")
  signatureHash(t[1])

macro registerInterfaceDecl(sym: typed, body: untyped, constr: untyped) =
  let k = getInterfaceKey(sym)
  interfaceDecls[k] = body
  constructorDecls[k] = constr

proc to*[T: ref](a: T, I: typedesc[Interface]): I {.inline.} =
  when T is I:
    a
  else:
    I(private_vTable: getVTable(I.VTable, T), private_obj: packObj(a))

proc ifaceImpl*(name: NimNode, body: NimNode, addConverter: bool): NimNode =
  result = newNimNode(nnkStmtList)

  let iName = ident($name)
  let converterName = ident("to" & $name)
  let vTableTypeName = ident("InterfaceVTable" & $name)
  var vTableType = newNimNode(nnkRecList)
  let vTableConstr = newTree(nnkObjConstr, vTableTypeName)
  let genericT = ident("T")
  let functions = newNimNode(nnkStmtList)
  let mixins = newNimNode(nnkStmtList)
  let upackedThis = ident"unpackedThis"
  let ifaceDecl = newNimNode(nnkStmtList)

  for i, p in body:
    p.expectKind(nnkProcDef)
    ifaceDecl.add(copyNimTree(p))
    mixins.add(newTree(nnkMixinStmt, p.name))
    let pt = newTree(nnkProcTy, copyNimTree(p.params), newEmptyNode())
    pt.addPragma(ident"nimcall")
    var retType = pt[0][0]
    if retType.kind == nnkEmpty: retType = ident"void"
    pt[0].insert(1, newIdentDefs(ident"this", ident"RootRef"))
    let fieldName = ident("<" & $i & ">" & $p.name)
    vTableType.add(newIdentDefs(fieldName, pt))

    let lambdaCall = newCall(p.name)
    lambdaCall.add(upackedThis)

    let vCall = newTree(nnkCall, newTree(nnkDotExpr, newTree(nnkDotExpr, ident"this", ident"private_vTable"), fieldName))
    vCall.add(newTree(nnkDotExpr, ident"this", ident"private_obj"))

    for a in 1 ..< p.params.len:
      let par = p.params[a]
      for b in 0 .. par.len - 3:
        lambdaCall.add(par[b])
        vCall.add(par[b])

    let lambdaBody = quote do:
      var `upackedThis`: `genericT`
      unpackObj(this, `upackedThis`)
      forceReturnValue(`retType`, checkRequiredMethod(`lambdaCall`, `iName`))

    let lam = newTree(nnkLambda, newEmptyNode(), newEmptyNode(), newEmptyNode(), pt[0], newEmptyNode(), newEmptyNode(), lambdaBody)
    # lam.addPragma(newTree(nnkExprColonExpr, ident"stackTrace", ident"off"))

    vTableConstr.add(newTree(nnkExprColonExpr, fieldName, lam))

    p.params.insert(1, newIdentDefs(ident"this", iName))

    p.body = vCall
    p.addPragma(ident"inline")
    p.addPragma(newTree(nnkExprColonExpr, ident"stackTrace", ident"off"))

    functions.add(p)

  vTableType = newTree(nnkTypeSection, newTree(nnkTypeDef, vTableTypeName, newEmptyNode(), newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), vTableType)))

  result.add quote do:
    `vTableType`
    type
      `iName` = Interface[`vTableTypeName`]
    proc initVTable(t: typedesc[`vTableTypeName`], `genericT`: typedesc): `vTableTypeName` =
      `mixins`
      `vTableConstr`
    `functions`

  if addConverter:
    result.add quote do:
      converter `converterName`[T: ref](a: T): `iName` {.inline.} =
        to(a, `iName`)

  result.add quote do:
    registerInterfaceDecl(`iName`, `ifaceDecl`, `vTableConstr`)

macro iface*(name: untyped, body: untyped): untyped =
  result = ifaceImpl(name, body, true)
  # echo repr result

proc getInterfaceDecl*(interfaceTypedescSym: NimNode): NimNode =
  interfaceDecls[getInterfaceKey(interfaceTypedescSym)]

macro localIfaceConvert*(ifaceType: typedesc[Interface], o: typed): untyped =
  let constr = constructorDecls[getInterfaceKey(ifaceType)]
  let genericT = ident"T"
  result = quote do:
    type `genericT` = type(`o`)
    let vt {.global.} = `constr`
    `ifaceType`(private_vTable: unsafeAddr vt, privateObj: packObj(`o`))
