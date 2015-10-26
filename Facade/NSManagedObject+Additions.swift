//
//  NSManagedObject+Additions.swift
//  Facade
//
//  Created by Olivier THIERRY on 19/07/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public extension NSManagedObject {
  
  /// Creates a new Object of type A and insert it to the given managedObjectContext
  /// if provided, other uses the default managedObjectContext provided by provider B
  ///
  /// :param inManagedObjectContext The context in which the object should be inserted (optional)
  /// :return A new instance of the ManagedObject
  class func create(inManagedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext) -> Self {
    return self.init(
      entity: entityDescription,
      insertIntoManagedObjectContext: inManagedObjectContext)
  }
  
  /// Deletes an object from the store
  ///
  /// :param object The object to delete
  func delete() {
    if let managedObjectContext = managedObjectContext {
      managedObjectContext.performBlockAndWait {
        managedObjectContext.deleteObject(self)
      }
    }
  }
  
  /// Returns the NSEntityDescription attached to Entity A
  ///
  /// :return an instance of NSEntityDescription
  public class var entityDescription : NSEntityDescription {
    let entityName = NSStringFromClass(self)
      .componentsSeparatedByString(".").last!
    
    return NSEntityDescription.entityForName(
      entityName,
      inManagedObjectContext: Stack.sharedInstance.mainManagedObjectContext)!
  }  
}
