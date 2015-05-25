//
//  ManagedObjectQuery.swift
//  Save
//
//  Created by Olivier THIERRY on 05/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public class Query<A: NSManagedObject> {
  
  private(set) var entity : NSEntityDescription
  private(set) var managedObjectContext : NSManagedObjectContext
  private(set) var fetchRequest : NSFetchRequest

  private var predicates: [NSPredicate]

  /// If set to true, uniq values will be returned from the store
  /// NOTE: if set to true, the query must be executed as Dictionnary
  /// result type
  public var distinct: Bool = false {
    didSet {
      self.fetchRequest.returnsDistinctResults = distinct
    }
  }
  
  /// Use this property to set the limit of the number of objects to fetch
  public var limit: Int = 0 {
    didSet {
      self.fetchRequest.fetchLimit = limit
    }
  }
  
  /// Use this property to restrict the properties of entity A to fetch
  /// from the store
  public var properties: [AnyObject] = [] {
    didSet {
      self.fetchRequest.propertiesToFetch = properties
    }
  }
  
  /// Designed initializer
  ///
  /// :param entity the entity description the request should be attached to
  /// :param managedObjectContext the managedObjectContext the request should be executed against
  required public init(entity: NSEntityDescription, managedObjectContext: NSManagedObjectContext) {
    self.entity = entity
    self.managedObjectContext = managedObjectContext
    self.fetchRequest = NSFetchRequest(entityName: entity.name!)
    self.predicates = []
  }
  
  /// Assign sorting order to the query results
  ///
  /// :param: sortStr The string describing the sort order of the query results
  /// (e.g: "age ASC", "age", "age ASC, id DESC")
  /// :return self
  public func sort(sortStr: String) -> Self {
    let components = sortStr.componentsSeparatedByString(",").map {
      component in component.componentsSeparatedByString(" ")
    }
    
    fetchRequest.sortDescriptors = components.map { component in
      if component.count > 2 {
        fatalError("sort(\(sortStr)) unrecognized format")
      } else if component.count == 2 {
        return NSSortDescriptor(key: component[0], ascending: component[1] == "ASC")
      } else {
        return NSSortDescriptor(key: component[0], ascending: true)
      }
    }
    
    return self
  }
  
  /// restrict the results to objects where :key's value is contained in :objects
  ///
  /// :param: key the entity's property name
  /// :param: containedIn the values to match againsts
  /// :return: self
  public func with(key: String, containedIn objects: [AnyObject]) -> Self
  {
    predicates.append(
      NSPredicate(
        format: "\(key) IN %@",
        argumentArray: [objects]))
    return self
  }

  /// restrict the results to objects where :key's value is not contained in :objects
  ///
  /// :param: key the entity's property name
  /// :param: notContainedIn the values to match againsts
  /// :return: self
  public func with(key: String, notContainedIn objects: [AnyObject]) -> Self {
    predicates.append(
      NSPredicate(
        format: "NOT (\(key) IN %@)",
        argumentArray: [objects]))
    return self
  }

  /// restrict the results to objects where :key's value contains the sequence string
  ///
  /// :param: key the entity's property name
  /// :param: value the sequence to match
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, containing value: String, caseSensitive: Bool = true,
    diacriticSensitive: Bool = true) -> Self {
    let modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    predicates.append(
      NSPredicate(
        format: "\(key) CONTAINS\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's value is LIKE the given pattern
  ///
  /// :param: key the entity's property name
  /// :param: LIKE pattern
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, like value: String, caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> Self {
    let modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    predicates.append(
      NSPredicate(
        format: "\(key) LIKE\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains all the given values
  ///
  /// :param: key the entity's property name
  /// :param: values the values the entity's set/array must contain
  /// :return: self
  public func with(key: String, containingAll values: [AnyObject]) -> Self {
    predicates.append(
      NSPredicate(
        format: "ALL \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains none of the given values
  ///
  /// :param: key the entity's property name
  /// :param: values the values the entity's set/array must not contain
  /// :return: self
  public func with(key: String, containingNone values: [AnyObject]) -> Self {
    predicates.append(
      NSPredicate(
        format: "NONE \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains any of the given values
  ///
  /// :param: key the entity's property name
  /// :param: values the values the entity's set/array can contain
  /// :return: self
  public func with(key: String, containingAny values: [AnyObject]) -> Self {
    predicates.append(
      NSPredicate(
        format: "ANY \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's must exist or not
  ///
  /// :param: key the entity's property name
  /// :param: exists true if the key must exists, false otherwise
  /// :return: self
  public func with(key: String, existing exists: Bool) -> Self {
    let matcher = exists ? "!=" : "=="
    predicates.append(
      NSPredicate(
        format: "\(key) \(matcher) NIL"))
    return self
  }
  
  /// restrict the results to objects where :key's must have the given suffix
  ///
  /// :param: key the entity's property name
  /// :param: endingWith the suffix
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, endingWith suffix: String, caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> Self {
    let modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    predicates.append(
      NSPredicate(
        format: "\(key) ENDSWITH\(modifier) %@",
        argumentArray: [suffix]))
    return self
  }

  /// restrict the results to objects where :key's must have the given prefix
  ///
  /// :param: key the entity's property name
  /// :param: startingWith the prefix
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, startingWith prefix: String, caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> Self {
    let modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    predicates.append(
      NSPredicate(
        format: "\(key) BEGINSWITH\(modifier) %@",
        argumentArray: [prefix]))
    return self
  }

  /// restrict the results to objects where :key's must be equal to the given value
  ///
  /// :param: key the entity's property name
  /// :param: equalTo the value
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, equalTo value: AnyObject, caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> Self {
    var modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    if modifier == "" {
      modifier = "="
    }
    predicates.append(
      NSPredicate(
        format: "\(key) =\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be equal to the given value
  ///
  /// :param: key the entity's property name
  /// :param: equalTo the value
  /// :param: caseSensitive consider the search case sensitive
  /// :param: diacriticSensitive consider the search diacritic sensitive
  /// :return: self
  public func with(key: String, notEqualTo value: AnyObject, caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> Self {
    let modifier = modifierFor(
      caseSensitive: caseSensitive,
      diacriticSensitive: diacriticSensitive)
    predicates.append(
      NSPredicate(
        format: "\(key) !=\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than the value
  ///
  /// :param: key the entity's property name
  /// :param: greaterThan the value
  /// :return: self
  public func with(key: String, greaterThan value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) > %@",
        argumentArray: [value]))
    return self
  }
  
  /// restrict the results to objects where :key's must not be greater than or equal the value
  ///
  /// :param: key the entity's property name
  /// :param: greaterThanOrEqual the value
  /// :return: self
  public func with(key: String, greaterThanOrEqual value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) >= %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than the value
  ///
  /// :param: key the entity's property name
  /// :param: greaterThan the value
  /// :return: self
  public func with(key: String, greaterThan value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) > %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than or equal the value
  ///
  /// :param: key the entity's property name
  /// :param: greaterThanOrEqual the value
  /// :return: self
  public func with(key: String, greaterThanOrEqual value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) >= %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than the value
  ///
  /// :param: key the entity's property name
  /// :param: lowerThan the value
  /// :return: self
  public func with(key: String, lowerThan value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) < %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than or equal the value
  ///
  /// :param: key the entity's property name
  /// :param: lowerThanOrEqual the value
  /// :return: self
  public func with(key: String, lowerThanOrEqual value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) <= %@",
        argumentArray: [value]))
    return self
  }
  
  /// restrict the results to objects where :key's must not be lower than the value
  ///
  /// :param: key the entity's property name
  /// :param: lowerThan the value
  /// :return: self
  public func with(key: String, lowerThan value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) < %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than or equal the value
  ///
  /// :param: key the entity's property name
  /// :param: lowerThanOrEqual the value
  /// :return: self
  public func with(key: String, lowerThanOrEqual value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) <= %@",
        argumentArray: [value]))
    return self
  }

  /// Execute the fetch request as a count operation
  /// 
  /// :return: the number of objects matching against query
  public func count() -> Int {
    if !predicates.isEmpty {
      fetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(predicates)
    }
    fetchRequest.includesSubentities = false
    var error: NSError?
    let count = managedObjectContext.countForFetchRequest(fetchRequest, error: &error)
    shouldHandleError(error)
    return count
  }

  /// Execute the fetch request and return its first optional object
  /// :return: optional object
  public func execute() -> A? {
    return execute().first
  }

  /// Execute the fetch request and return its objects
  /// :return: [objects]
  public func execute() -> [A] {
    fetchRequest.resultType = .ManagedObjectResultType
    return _execute() as! [A]
  }

  /// Execute the fetch request as Dictionnaries return type
  /// and return the first optional dictionnary
  /// :return: NSDictionary
  public func execute() -> NSDictionary? {
    return execute().first
  }

  /// Execute the fetch request as Dictionnaries return type
  /// :return: [NSDictionary]
  public func execute() -> [NSDictionary] {
    fetchRequest.resultType = .DictionaryResultType
    return _execute() as! [NSDictionary]
  }

  private func _execute() -> [AnyObject]? {
    if !predicates.isEmpty {
      fetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(predicates)
    }
    
    var error : NSError?
    let objects = managedObjectContext.executeFetchRequest(
      fetchRequest,
      error: &error
    )
    
    if shouldHandleError(error) {
      println("Error executing fetchRequest: \(fetchRequest). Error: \(error)")
      return []
    }
    
    return objects
  }
  
  private func modifierFor(caseSensitive: Bool = true, diacriticSensitive: Bool = true) -> String {
    if caseSensitive && diacriticSensitive {
      return ""
    }
    var modifier = "["
    if !caseSensitive {
      modifier += "c"
    }
    if !diacriticSensitive {
      modifier += "d"
    }
    modifier += "]"
    return modifier
  }

  private func shouldHandleError(error: NSError?) -> Bool {
    if error == nil {
      return false
    }
    // @TODO: Do some error handling via event system
    println("Error executing fetchRequest: \(fetchRequest). Error: \(error)")
    return true
  }
}