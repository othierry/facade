//
//  Operators.swift
//  Facade
//
//  Created by Olivier THIERRY on 19/07/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

// Common
infix operator <-  {}
infix operator </> {}

// child contexts
infix operator <>  {}
infix operator <<>> {}

// independent contexts (nodes)
infix operator <*> {}
infix operator <<*>> {}

public func <*>(left: Stack, right: String) -> NSManagedObjectContext {
  return left.registerIndependentContextWithIdentifier(right)
}

public func <<*>>(left: Stack, right: String) -> NSManagedObjectContext {
  return left.registerIndependentContextWithIdentifier(right, concurrencyType: .MainQueueConcurrencyType)
}

public func <>(left: NSManagedObjectContext, right: String) -> NSManagedObjectContext {
  return Facade.stack.registerChildContextWithIdentifier(right, parentManagedObjectContext: left)
}

public func <<>>(left: NSManagedObjectContext, right: String) -> NSManagedObjectContext {
  return Facade.stack.registerChildContextWithIdentifier(right, parentManagedObjectContext: left, concurrencyType: .MainQueueConcurrencyType)
}

/**
  Retrieve an object with the specified ID in the context or creates a fault
  corresponding to that objectID

  - Parameters:
    - left: The managed object context to retrieve the object from
    - right: The managed object to be retrieved

  - Returns: Managed object of type `A`

  This is equivalent to:

  ```
  left.objectWithID(right.objectID)
  ```

  SeeAlso NSManagedObject.objectWithID(_:NSManagedObjectID)
*/
public func <-<A: NSManagedObject>(left: NSManagedObjectContext, right: A) -> A {
  var object: A!
  left.performBlockAndWait {
    object = left.objectWithID(right.objectID) as! A
  }
  return object
}

/**
  Register a new child context with `.PrivateQueueConcurrencyType`
  concurrency type. The Child context is uniq by its given identifier.
  
  The registered context has it's parent context set to `Stack.mainManagedObjectContext`

  - Parameters:
    - left: The CoreData's stack
    - right: The identifier of the child context

  - Returns: the registered child context

  This is equivalent to:

  ```
  left.registerChildContextWithIdentifier(right)
  ```

*/
public func <>(left: Stack, right: String) -> NSManagedObjectContext {
  return left.registerChildContextWithIdentifier(right)
}


/**
 Register a new child context with `.MainQueueConcurrencyType`
 concurrency type. The Child context is uniq by its given identifier.
 
 The registered context has it's parent context set to `Stack.mainManagedObjectContext`
 
 - Parameters:
 - left: The CoreData's stack
 - right: The identifier of the child context
 
 - Returns: the registered child context
 
 This is equivalent to:
 
 ```
 left.registerChildContextWithIdentifier(right)
 ```
 
 */
public func <<>>(left: Stack, right: String) -> NSManagedObjectContext {
  return left.registerChildContextWithIdentifier(right, concurrencyType: .MainQueueConcurrencyType)
}

/**
  Unregister a child context with the given identifier
  If no suck context exists. The fonction will do nothing.

  - Parameters:
    - left: The CoreData's stack
    - right: The identifier of the child context

  This is equivalent to:

  ```
  left.unregisterChildContextWithIdentifier(right)
  ```

*/
public func </>(left: Stack, right: String) {
  return left.unregisterContextWithIdentifier(right)
}
