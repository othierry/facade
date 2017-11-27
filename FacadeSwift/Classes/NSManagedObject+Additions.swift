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
  
  /// Returns the entity class name as `String`
  ///
  /// :return String
  public class var entityName: String {
    return NSStringFromClass(self)
      .components(separatedBy: ".")
      .last!
  }
  
  /// Returns the NSEntityDescription attached to Entity A
  ///
  /// :return an instance of NSEntityDescription
  public class var entityDescription : NSEntityDescription {
    return NSEntityDescription.entity(
      forEntityName: entityName,
      in: Stack.sharedInstance.mainManagedObjectContext)!
  }

  /// Creates a new Object of type A and insert it to the given managedObjectContext
  /// if provided, other uses the default managedObjectContext provided by provider B
  ///
  /// :param inManagedObjectContext The context in which the object should be inserted (optional)
  /// :return A new instance of the ManagedObject
  class func create(inManagedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext) -> Self {
    return createAutoTyped(inManagedObjectContext)
  }

  /// Deletes an object from the store asynchronously
  ///
  /// :param object The object to delete
  func delete() {
    guard let managedObjectContext = managedObjectContext else {
      return
    }
    
    managedObjectContext.perform {
      managedObjectContext.delete(self)
    }
  }

  /// Deletes an object from the store synchronously
  ///
  /// :param object The object to delete
  func deleteSync() {
    guard let managedObjectContext = managedObjectContext else {
      return
    }
    
    managedObjectContext.performAndWait {
      managedObjectContext.delete(self)
      managedObjectContext.processPendingChanges()
    }
  }

  fileprivate class func createAutoTyped<A: NSManagedObject>(
    _ inManagedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext) -> A
  {
    let object = NSEntityDescription.insertNewObject(
      forEntityName: entityName,
      into: inManagedObjectContext) as! A
    
    try! inManagedObjectContext.obtainPermanentIDs(for: [object])
    
    return object
  }
}
