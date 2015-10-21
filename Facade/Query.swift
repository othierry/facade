//
//  Query.swift
//  Save
//
//  Created by Olivier THIERRY on 05/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public struct QueryOptions : RawOptionSetType, BooleanType {

  private let value: UInt
  
  public var boolValue: Bool {
    return value != 0
  }
  
  public var rawValue: UInt {
    return value
  }
  
  public init(nilLiteral: ()) {
    self.value = 0
  }
  
  public init(_ value: UInt = 0) {
    self.value = value
  }
  
  public init(rawValue value: UInt) {
    self.value = value
  }
  
  public func has(options: QueryOptions) -> Bool {
    return self & options ? true : false
  }
  
  public static var allZeros: QueryOptions { return self(0) }
  public static var None: QueryOptions { return self(0b0000) }
  public static var CaseInsensitive: QueryOptions { return self(0b0001) }
  public static var DiacriticInsensitive: QueryOptions { return self(0b0010) }
}

public class ElasticQuery<A: NSManagedObject> {
  public private(set) var query: Query<A>
  public var batchSize: Int = 100
  public var results: [A] = []
  
  public required init(query: Query<A>) {
    self.query = query
  }
  
  public func loadMore() -> [A] {
    if canLoadMore {
      query.limit(batchSize)
      query.offset(results.count)
      let batch = query.execute() as [A]
      results += batch
      return batch
    } else {
      return []
    }
  }
  
  public var canLoadMore: Bool {
    return totalNumberOfResults > results.count
  }
  
  public lazy var totalNumberOfResults: Int = {
    return self.query.count()
    }()
}

public class Query<A: NSManagedObject> {
  
  public private(set) var managedObjectContext : NSManagedObjectContext
  public private(set) var fetchRequest : NSFetchRequest

  internal var predicates: [NSPredicate]
  
  /// Designed initializer
  ///
  /// :param entity the entity description the request should be attached to
  /// :param managedObjectContext the managedObjectContext the request should be executed against
  required public init() {
    managedObjectContext = Facade.stack.mainManagedObjectContext
    fetchRequest = NSFetchRequest(entityName: A.entityDescription.name!)
    predicates = []
  }

  public class func or(queries: [Query<A>]) -> Query<A> {
    let predicates = queries.flatMap { $0.predicates }
    let query = Query<A>()
    query.predicates = [NSCompoundPredicate.orPredicateWithSubpredicates(predicates)]
    return query
  }
  
  /// Shortcut accessor to execute the query as [A]
  public func all() -> [A] {
    return execute()
  }
  
  /// Shortcut accessor to execute the query as A?
  public func first() -> A? {
    if let primaryKey = Facade.stack.config.modelPrimaryKey {
      sort("\(primaryKey) ASC")
    }
    return limit(1).execute()
  }

  /// Shortcut accessor to execute the query as A?
  public func last() -> A? {
    if let primaryKey = Facade.stack.config.modelPrimaryKey {
      sort("\(primaryKey) DESC")
    }
    return limit(1).execute()
  }
  
  public func elastic() -> ElasticQuery<A> {
    return ElasticQuery(query: self)
  }

  /// If set to true, uniq values will be returned from the store
  /// NOTE: if set to true, the query must be executed as Dictionnary
  /// result type
  public func distinct(on: String? = nil) -> Self {
    fetchRequest.returnsDistinctResults = true
    if let on = on {
      fetch([on])
    }
    return self
  }
  
  /// Use this property to set the limit of the number of objects to fetch
  public func limit(x: Int) -> Self {
    fetchRequest.fetchLimit = x
    return self
  }
  
  public func offset(x: Int) -> Self {
    fetchRequest.fetchOffset = x
    return self
  }
  
  public func fetchBatchSize(x: Int) -> Self {
    fetchRequest.fetchBatchSize = x
    return self
  }
  
  public func prefetch(relations: [AnyObject]) -> Self {
    fetchRequest.relationshipKeyPathsForPrefetching = relations
    return self
  }
  
  public func faults(returnsFaults: Bool) -> Self {
    fetchRequest.returnsObjectsAsFaults = returnsFaults
    return self
  }
  
  /// Use this property to restrict the properties of entity A to fetch
  /// from the store
  public func fetch(properties: [AnyObject]) -> Self {
    fetchRequest.propertiesToFetch = properties
    return self
  }
  
  public func inManagedObjectContext(managedObjectContext: NSManagedObjectContext) -> Self {
    self.managedObjectContext = managedObjectContext
    return self
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
  public func with(key: String, containing value: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
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
  public func with(key: String, like value: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
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
  public func with(key: String, endingWith suffix: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
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
  public func with(key: String, startingWith prefix: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
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
  public func with(key: String, equalTo value: AnyObject, options: QueryOptions = .None) -> Self {
    var modifier = modifierFor(options)
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
  public func with(key: String, notEqualTo value: AnyObject, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
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

  public func delete() {
    fetchRequest.includesPropertyValues = false
    for object in execute() as [A] {
      managedObjectContext.deleteObject(object)
    }
    Facade.stack.commitSync(managedObjectContext)
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

  /// Execute the fetch request as NSManagedObjectID return type
  /// :return: [NSManagedObjectID]
  public func execute() -> [NSManagedObjectID] {
    fetchRequest.resultType = .ManagedObjectIDResultType
    return _execute() as! [NSManagedObjectID]
  }

  private func _execute() -> [AnyObject]? {    
    if !predicates.isEmpty {
      fetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(predicates)
    }
    
    var error : NSError?
    var objects: [AnyObject]?
    
    managedObjectContext.performBlockAndWait {
      objects = self.managedObjectContext.executeFetchRequest(
        self.fetchRequest,
        error: &error)
    }

    if shouldHandleError(error) {
      println("Error executing fetchRequest: \(fetchRequest). Error: \(error)")
      return []
    }

    return objects
  }
  
  private func modifierFor(options: QueryOptions) -> String {
    let modifiers = [(options.has(.CaseInsensitive), "c"), (options.has(.DiacriticInsensitive), "d")]
    let activeModifiers = "".join(modifiers.filter { $0.0 }.map { $0.1 })
    return Swift.count(activeModifiers) > 0 ? "[\(activeModifiers)]" : ""
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