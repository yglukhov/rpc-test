import unittest
import iface

iface Animal:
  proc say(): string
  proc test2()

type
  Dog = ref object
    testCalled: bool

proc say(d: Dog): string = "bark"
proc test2(d: Dog) =
  d.testCalled = true

proc doSmth(a: Animal): string =
  a.test2()
  a.say()

proc createVoldemortObject(): Animal =
  type
    Hidden = ref object
  proc say(h: Hidden): string = "hsss"
  proc test2(h: Hidden) = discard
  localIfaceConvert(Animal, Hidden())

suite "iface":
  test "animals":
    let d = Dog.new()
    check doSmth(d) == "bark"
    check d.testCalled

  test "animals static":
    const s = static:
      let d = Dog.new()
      let res = doSmth(d)
      doAssert(d.testCalled)
      res
    check s == "bark"

  test "implement interface in proc (voldemort)":
    check doSmth(createVoldemortObject()) == "hsss"
