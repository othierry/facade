//
//  Query.swift
//  Save
//
//  Created by Olivier THIERRY on 05/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public struct QueryOptions: OptionSet {

  public let rawValue: UInt

  public init(rawValue: UInt) {
      self.rawValue = rawValue
  }

  public var boolValue: Bool {
    return rawValue != 0
  }

  public func has(_ options: QueryOptions) -> Bool {
    return self.intersection(options) == options
  }
  
  public static let None = QueryOptions(rawValue: 0)
  public static let CaseInsensitive = QueryOptions(rawValue: 1)
  public static let DiacriticInsensitive = QueryOptions(rawValue: 1 << 1)
  
}

open class ElasticQuery<A: NSManagedObject> {
  open fileprivate(set) var query: Query<A>
  open var batchSize: Int = 100
  open var results: [A] = []
  
  public required init(query: Query<A>) {
    self.query = query
  }
  
  open func loadMore() -> [A] {
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
  
  open var canLoadMore: Bool {
    return totalNumberOfResults > results.count
  }
  
  open lazy var totalNumberOfResults: Int = {
    return self.query.count()
    }()
}

open class Query<A: NSManagedObject> {
  
  open fileprivate(set) var managedObjectContext: NSManagedObjectContext
  open fileprivate(set) var fetchRequest: NSFetchRequest<NSFetchRequestResult>

  internal var predicates: [NSPredicate]
  
  /// Designed initializer
  ///
  /// :param entity the entity description the request should be attached to
  /// :param managedObjectContext the managedObjectContext the request should be executed against
  required public init(_ type: A.Type) {
    managedObjectContext = Stack.sharedInstance.mainManagedObjectContext
    fetchRequest = NSFetchRequest(entityName: type.entityDescription.name!)
    predicates = []
  }

  open class func or(_ queries: [Query<A>]) -> Query<A> {
    let predicates = queries.map { NSCompoundPredicate(andPredicateWithSubpredicates: $0.predicates) }
    let query = Query(A.self)
    query.predicates = [NSCompoundPredicate(orPredicateWithSubpredicates: predicates)]
    return query
  }

  /// Shortcut accessor to execute the query as [A]
  open func all() -> [A] {
    return execute()
  }
  
  /// Shortcut accessor to execute the query as A?
  open func first() -> A? {
    if let primaryKey = facade_stack.config.modelPrimaryKey {
      sort("\(primaryKey) ASC")
    }
    return limit(1).execute()
  }

  /// Shortcut accessor to execute the query as A?
  open func last() -> A? {
    if let primaryKey = facade_stack.config.modelPrimaryKey {
      sort("\(primaryKey) DESC")
    }
    return limit(1).execute()
  }
  
  open func elastic() -> ElasticQuery<A> {
    return ElasticQuery(query: self)
  }

  /// If set to true, uniq values will be returned from the store
  /// NOTE: if set to true, the query must be executed as Dictionnary
  /// result type
  @discardableResult
  open func distinct(_ on: String? = nil) -> Self {
    fetchRequest.returnsDistinctResults = true
    if let on = on {
      fetch([on])
    }
    return self
  }
  
  /// Use this property to set the limit of the number of objects to fetch
  @discardableResult
  open func limit(_ x: Int) -> Self {
    fetchRequest.fetchLimit = x
    return self
  }
  
  @discardableResult
  open func offset(_ x: Int) -> Self {
    fetchRequest.fetchOffset = x
    return self
  }
  
  @discardableResult
  open func fetchBatchSize(_ x: Int) -> Self {
    fetchRequest.fetchBatchSize = x
    return self
  }
  
  @discardableResult
  open func prefetch(_ relations: [String]) -> Self {
    fetchRequest.relationshipKeyPathsForPrefetching = relations
    return self
  }
  
  @discardableResult
  open func faults(_ returnsFaults: Bool) -> Self {
    fetchRequest.returnsObjectsAsFaults = returnsFaults
    return self
  }
  
  @discardableResult
  open func refresh(_ refreshRefetchedObjects: Bool) -> Self {
    fetchRequest.shouldRefreshRefetchedObjects = refreshRefetchedObjects
    return self
  }
  
  @discardableResult
  open func groupBy(_ properties: [Any]) -> Self {
    fetchRequest.propertiesToGroupBy = properties
    return self
  }
  
  /// Use this property to restrict the properties of entity A to fetch
  /// from the store
  @discardableResult
  open func fetch(_ properties: [Any]) -> Self {
    fetchRequest.propertiesToFetch = properties
    return self
  }
  
  @discardableResult
  open func inManagedObjectContext(_ managedObjectContext: NSManagedObjectContext) -> Self {
    self.managedObjectContext = managedObjectContext
    return self
  }
  
  open func toFetchedResultsController(
    sectionNameKeyPath: String? = nil,
    cacheName: String? = nil) -> NSFetchedResultsController<A>
  {
    setPredicate()
    
    return NSFetchedResultsController(
      fetchRequest: self.fetchRequest as! NSFetchRequest<A>,
      managedObjectContext: self.managedObjectContext,
      sectionNameKeyPath: sectionNameKeyPath,
      cacheName: cacheName)
  }
  
  /// Assign sorting order to the query results
  ///
  /// - parameter sortStr: The string describing the sort order of the query results
  /// (e.g: "age ASC", "age", "age ASC, id DESC")
  /// :return self
  @discardableResult
  open func sort(_ sortStr: String) -> Self {
    let components = sortStr.components(separatedBy: ",").map {
      component in component.components(separatedBy: " ")
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
  /// - parameter key: the entity's property name
  /// - parameter containedIn: the values to match againsts
  /// :return: self
  open func with(_ key: String, containedIn objects: [Any]) -> Self
  {
    predicates.append(
      NSPredicate(
        format: "\(key) IN %@",
        argumentArray: [objects]))
    return self
  }

  /// restrict the results to objects where :key's value is not contained in :objects
  ///
  /// - parameter key: the entity's property name
  /// - parameter notContainedIn: the values to match againsts
  /// :return: self
  open func with(_ key: String, notContainedIn objects: [Any]) -> Self {
    predicates.append(
      NSPredicate(
        format: "NOT (\(key) IN %@)",
        argumentArray: [objects]))
    return self
  }

  /// restrict the results to objects where :key's value contains the sequence string
  ///
  /// - parameter key: the entity's property name
  /// - parameter value: the sequence to match
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, containing value: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
    predicates.append(
      NSPredicate(
        format: "\(key) CONTAINS\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's value is LIKE the given pattern
  ///
  /// - parameter key: the entity's property name
  /// - parameter LIKE: pattern
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, like value: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
    predicates.append(
      NSPredicate(
        format: "\(key) LIKE\(modifier) %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains all the given values
  ///
  /// - parameter key: the entity's property name
  /// - parameter values: the values the entity's set/array must contain
  /// :return: self
  open func with(_ key: String, containingAll values: [Any]) -> Self {
    predicates.append(
      NSPredicate(
        format: "ALL \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains none of the given values
  ///
  /// - parameter key: the entity's property name
  /// - parameter values: the values the entity's set/array must not contain
  /// :return: self
  open func with(_ key: String, containingNone values: [Any]) -> Self {
    predicates.append(
      NSPredicate(
        format: "NONE \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's set/array contains any of the given values
  ///
  /// - parameter key: the entity's property name
  /// - parameter values: the values the entity's set/array can contain
  /// :return: self
  open func with(_ key: String, containingAny values: [Any]) -> Self {
    predicates.append(
      NSPredicate(
        format: "ANY \(key) IN %@",
        argumentArray: [values]))
    return self
  }

  /// restrict the results to objects where :key's must exist or not
  ///
  /// - parameter key: the entity's property name
  /// - parameter exists: true if the key must exists, false otherwise
  /// :return: self
  open func with(_ key: String, existing exists: Bool) -> Self {
    let matcher = exists ? "!=" : "=="
    predicates.append(
      NSPredicate(
        format: "\(key) \(matcher) NIL"))
    return self
  }
  
  /// restrict the results to objects where :key's must have the given suffix
  ///
  /// - parameter key: the entity's property name
  /// - parameter endingWith: the suffix
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, endingWith suffix: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
    predicates.append(
      NSPredicate(
        format: "\(key) ENDSWITH\(modifier) %@",
        argumentArray: [suffix]))
    return self
  }

  /// restrict the results to objects where :key's must have the given prefix
  ///
  /// - parameter key: the entity's property name
  /// - parameter startingWith: the prefix
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, startingWith prefix: String, options: QueryOptions = .None) -> Self {
    let modifier = modifierFor(options)
    predicates.append(
      NSPredicate(
        format: "\(key) BEGINSWITH\(modifier) %@",
        argumentArray: [prefix]))
    return self
  }

  /// restrict the results to objects where :key's must be equal to the given value
  ///
  /// - parameter key: the entity's property name
  /// - parameter equalTo: the value
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, equalTo value: Any?, options: QueryOptions = .None) -> Self {
    guard value != nil else {
      return with(key, existing: false)
    }
    
    var modifier = modifierFor(options)
    if modifier == "" {
      modifier = "="
    }
    predicates.append(
      NSPredicate(
        format: "\(key) =\(modifier) %@",
        argumentArray: [value!]))
    return self
  }

  /// restrict the results to objects where :key's must not be equal to the given value
  ///
  /// - parameter key: the entity's property name
  /// - parameter equalTo: the value
  /// - parameter caseSensitive: consider the search case sensitive
  /// - parameter diacriticSensitive: consider the search diacritic sensitive
  /// :return: self
  open func with(_ key: String, notEqualTo value: Any?, options: QueryOptions = .None) -> Self {
    guard value != nil else {
      return with(key, existing: true)
    }

    let modifier = modifierFor(options)
    predicates.append(
      NSPredicate(
        format: "\(key) !=\(modifier) %@",
        argumentArray: [value ?? "NIL"]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter greaterThan: the value
  /// :return: self
  open func with(_ key: String, greaterThan value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) > %@",
        argumentArray: [value]))
    return self
  }
  
  /// restrict the results to objects where :key's must not be greater than or equal the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter greaterThanOrEqual: the value
  /// :return: self
  open func with(_ key: String, greaterThanOrEqual value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) >= %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter greaterThan: the value
  /// :return: self
  open func with(_ key: String, greaterThan value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) > %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be greater than or equal the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter greaterThanOrEqual: the value
  /// :return: self
  open func with(_ key: String, greaterThanOrEqual value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) >= %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter lowerThan: the value
  /// :return: self
  open func with(_ key: String, lowerThan value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) < %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than or equal the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter lowerThanOrEqual: the value
  /// :return: self
  open func with(_ key: String, lowerThanOrEqual value: Double) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) <= %@",
        argumentArray: [value]))
    return self
  }
  
  /// restrict the results to objects where :key's must not be lower than the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter lowerThan: the value
  /// :return: self
  open func with(_ key: String, lowerThan value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) < %@",
        argumentArray: [value]))
    return self
  }

  /// restrict the results to objects where :key's must not be lower than or equal the value
  ///
  /// - parameter key: the entity's property name
  /// - parameter lowerThanOrEqual: the value
  /// :return: self
  open func with(_ key: String, lowerThanOrEqual value: Int) -> Self {
    predicates.append(
      NSPredicate(
        format: "\(key) <= %@",
        argumentArray: [value]))
    return self
  }
  
  /// add raw predicate
  ///
  /// - parameter raw: the raw query string
  /// - parameter args: varargs arguments to interpolate the query string
  /// :return: self
  open func with(_ raw: String, _ args: Any...) -> Self {
    predicates.append(
      NSPredicate(
        format: raw,
        argumentArray: args))
    
    return self
  }

  /// Execute the fetch request as a count operation
  /// 
  /// :return: the number of objects matching against query
  open func count() -> Int {
    setPredicate()
    
    fetchRequest.includesSubentities = false
    
    var count: Int!
   
    managedObjectContext.performAndWait {
      do {
        count = try self.managedObjectContext.count(for: self.fetchRequest)
      } catch let error as NSError {
        self.shouldHandleError(error)
      }
    }
    
    return count
  }

  open func delete() {
    setPredicate()
    
    // We do not need to load any values
    fetchRequest.includesPropertyValues = false

    managedObjectContext.performAndWait {
      for object in self.execute() as [A] {
        self.managedObjectContext.delete(object)
      }
    }
  }
  
  @available(iOS 9.0, *)
  open func batchDelete() {
    setPredicate()

    let batchRequest = NSBatchDeleteRequest(
      fetchRequest: self.fetchRequest
    )
    
    managedObjectContext.performAndWait {
      do {
        try self.managedObjectContext.execute(batchRequest)
      } catch let error as NSError {
        if self.shouldHandleError(error) {
          print("Error executing batch deleted request: \(batchRequest), fetchRequest: \(self.fetchRequest) Error: \(error)")
        }
      }
    }
  }
  
  /// Execute the fetch request and return its first optional object
  /// :return: optional object
  open func execute() -> A? {
    return execute().first
  }

  /// Execute the fetch request and return its objects
  /// :return: [objects]
  open func execute() -> [A] {
    fetchRequest.resultType = .managedObjectResultType
    return _execute() as! [A]
  }

  /// Execute the fetch request as Dictionnaries return type
  /// and return the first optional dictionnary
  /// :return: NSDictionary
  open func execute() -> NSDictionary? {
    return execute().first
  }

  /// Execute the fetch request as Dictionnaries return type
  /// :return: [NSDictionary]
  open func execute() -> [NSDictionary] {
    fetchRequest.resultType = .dictionaryResultType
    return _execute() as! [NSDictionary]
  }

  /// Execute the fetch request as NSManagedObjectID return type
  /// :return: [NSManagedObjectID]
  open func execute() -> [NSManagedObjectID] {
    fetchRequest.resultType = .managedObjectIDResultType
    return _execute() as! [NSManagedObjectID]
  }

  fileprivate func _execute() -> [Any]? {
    setPredicate()
    
    var objects: [Any]?
    
    managedObjectContext.performAndWait {
      do {
        objects = try self.managedObjectContext.fetch(self.fetchRequest)
      } catch let error as NSError {
        if self.shouldHandleError(error) {
          print("Error executing fetchRequest: \(self.fetchRequest). Error: \(error)")
        }
        objects = []
      }
    }

    return objects
  }
  
  fileprivate func setPredicate() {
    if !predicates.isEmpty {
      fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    } else {
      fetchRequest.predicate = nil
    }
  }
  
  fileprivate func modifierFor(_ options: QueryOptions) -> String {
    let modifiers = [(options.has(.CaseInsensitive), "c"), (options.has(.DiacriticInsensitive), "d")]
    let activeModifiers = modifiers.filter { $0.0 }.map { $0.1 }.joined(separator: "")
    return activeModifiers.characters.count > 0 ? "[\(activeModifiers)]" : ""
  }

  @discardableResult
  fileprivate func shouldHandleError(_ error: NSError?) -> Bool {
    if error == nil {
      return false
    }
    // @TODO: Do some error handling via event system
    print("Error executing fetchRequest: \(fetchRequest). Error: \(String(describing: error))")
    return true
  }
}

public func facade_query<A: NSManagedObject>(_ type: A.Type) -> Query<A> {
  return Query(type)
}

public func facade_queryOr<A: NSManagedObject>(_ queries: [Query<A>]) -> Query<A> {
  return Query.or(queries)
}
