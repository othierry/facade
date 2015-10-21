//
//  Operators.swift
//  Facade
//
//  Created by Olivier THIERRY on 19/07/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

infix operator <-  {}
infix operator <>  {}
infix operator </> {}

public func <-<A: NSManagedObject>(left: NSManagedObjectContext, right: A) -> A {
  var object: A!
  left.performBlockAndWait {
    object = left.objectWithID(right.objectID) as! A
  }
  return object
}

public func <>(left: Stack, right: String) -> NSManagedObjectContext {
  return left.registerChildContextWithIdentifier(right)
}

public func </>(left: Stack, right: String) {
  return left.unregisterChildContextWithIdentifier(right)
}
