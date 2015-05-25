//
//  ManagedObjectInteractor.swift
//  Save
//
//  Created by Olivier THIERRY on 04/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public protocol ManagedObjectContextProvider {
  /// Impelement this accessor to return the default/main managedObjectContext
  static var managedObjectContext: NSManagedObjectContext { get }
}

public class Facade<A: NSManagedObject, B: ManagedObjectContextProvider> {
  
  /// Creates a new Object of type A and insert it to the given managedObjectContext
  /// if provided, other uses the default managedObjectContext provided by provider B
  ///
  /// :param inManagedObjectContext The context in which the object should be inserted (optional)
  /// :return A new instance of the ManagedObject
  public class func create(_ inManagedObjectContext: NSManagedObjectContext? = nil) -> A {
    return NSManagedObject(
      entity: entityDescription,
      insertIntoManagedObjectContext: (inManagedObjectContext ?? B.managedObjectContext)
    ) as! A
  }
  
  /// Save the given object A by persisting its changes to the store
  ///
  /// :param object The object to save
  /// :return true if the operation succeeded, false otherwise
  public class func save(object: A) -> Bool {
    var error: NSError?
    if let moc = object.managedObjectContext {
      if moc.save(&error) {
        return true
      } else {
        println("Error saving object \(object). Error: \(error)")
        return false
      }
    } else {
      return false
    }
  }
  
  /// Deletes an object from the store
  ///
  /// :param object The object to delete
  public class func delete(object: A) -> Void {
    object.managedObjectContext?.deleteObject(object)
  }
  
  /// Creates a Query to fetch one or many entities of type A in the store. The query is attached
  /// the the given managedObjectContext if provided, other uses the default managedObjectContext 
  /// provided by provider B
  ///
  /// :param inManagedObjectContext The context in which the object should be inserted (optional)
  /// :return a instance of Query object
  public class func query(_ managedObjectContext: NSManagedObjectContext? = nil) -> Query<A> {
    let query = Query<A>(
      entity: entityDescription,
      managedObjectContext: managedObjectContext ?? B.managedObjectContext)
    return query
  }
  
  /// Returns the NSEntityDescription attached to Entity A
  ///
  /// :return an instance of NSEntityDescription
  public class var entityDescription : NSEntityDescription {
    let entityName = NSStringFromClass(A.self)
      .componentsSeparatedByString(".").last!
    
    return NSEntityDescription.entityForName(
      entityName,
      inManagedObjectContext: B.managedObjectContext
    )!
  }
}