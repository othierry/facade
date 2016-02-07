//
//  Stack.swift
//  Facade
//
//  Created by Olivier THIERRY on 30/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public class Stack {
  
  public class Config {
    public var modelName: String?
    public var seedName: String?
    public var storeName: String? = NSBundle.mainBundle().bundleIdentifier
    public var storeType: String = NSSQLiteStoreType
    public var modelPrimaryKey: String?
    public var options: [NSObject : AnyObject] = [:]
  }
  
  enum DetachedManagedObjectContextType {
    case Child, Independent
  }
  
  public private(set) var config = Config()
 
  private var managedObjectContexts: [String : (type: DetachedManagedObjectContextType, managedObjectContext: NSManagedObjectContext)] = [:]

  private var childManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.type == .Child }
      .map { $1.managedObjectContext }
  }

  private var independentManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.type == .Independent }
      .map { $1.managedObjectContext }
    + [mainManagedObjectContext] // Include main context as independent
  }

  private init() {
    registerForManagedObjectContextNotifications(mainManagedObjectContext)
    registerForManagedObjectContextNotifications(rootManagedObjectContext)
  }
  
  deinit {
    unregisterForManagedObjectContextNotifications()
  }

  public func commit(managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext) {
    commit(managedObjectContext, withCompletionHandler: nil)
  }

  public func commit(
    managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext,
    withCompletionHandler completionHandler: (NSError? -> Void)?)
  {
    managedObjectContext.performBlock {
      if managedObjectContext.hasChanges {
        do {
          try managedObjectContext.save()

          dispatch_async(dispatch_get_main_queue()) {
            completionHandler?(nil)
          }
        } catch let error as NSError {
          print("[Facade.stack.commit] Error saving context \(managedObjectContext). Error: \(error)")
          dispatch_async(dispatch_get_main_queue()) {
            completionHandler?(error)
          }
        }
      } else {
        dispatch_async(dispatch_get_main_queue()) {
          completionHandler?(nil)
        }
      }
    }
  }

  public func commitSync(managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext) {
    managedObjectContext.performBlockAndWait {
      if managedObjectContext.hasChanges {
        do {
          try managedObjectContext.save()
        } catch let error as NSError {
          print("[Facade.stack.commitSync] Error saving context \(managedObjectContext). Error: \(error)")
        }
      }
    }
  }
  
  public func createManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType) -> NSManagedObjectContext {
    return  NSManagedObjectContext(
      concurrencyType: concurrencyType)
  }

  public func registerChildContextWithIdentifier(
    identifier: String,
    parentManagedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext,
    concurrencyType: NSManagedObjectContextConcurrencyType = .PrivateQueueConcurrencyType) -> NSManagedObjectContext {
    if let managedObjectContextContainer = managedObjectContexts[identifier] {
      guard managedObjectContextContainer.type == .Child else {
        fatalError("")
      }
      
      return managedObjectContextContainer.managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parentContext = parentManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = (.Child, managedObjectContext)
    
    return managedObjectContext
  }

  public func registerIndependentContextWithIdentifier(identifier: String, concurrencyType: NSManagedObjectContextConcurrencyType = .PrivateQueueConcurrencyType) -> NSManagedObjectContext {
    if let managedObjectContextContainer = managedObjectContexts[identifier] {
      guard managedObjectContextContainer.type == .Independent else {
        fatalError("")
      }
      
      return managedObjectContextContainer.managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parentContext = rootManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = (.Independent, managedObjectContext)
    
    return managedObjectContext
  }

  public func unregisterContextWithIdentifier(identifier: String) {
    guard let managedObjectContextContainer = managedObjectContexts[identifier] else {
      return
    }
    
    unregisterForManagedObjectContextNotifications(managedObjectContextContainer.managedObjectContext)
    
    managedObjectContextContainer.managedObjectContext.performBlock {
      managedObjectContextContainer.managedObjectContext.reset()
    }
    
    // managedObjectContext is retained by performBlock's block
    // so we can remove it now
    self.managedObjectContexts.removeValueForKey(identifier)
  }
  
  public func identifierForContext(managedObjectContext: NSManagedObjectContext) -> String? {
    for (identifier, contextContainer) in managedObjectContexts {
      if contextContainer.managedObjectContext === managedObjectContext {
        return identifier
      }
    }
    
    return nil
  }
  
  public func connect() throws {
    let storeURL = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent(self.config.storeName!)
      .URLByAppendingPathExtension("sqlite")

    try persistentStoreCoordinator.addPersistentStoreWithType(
      self.config.storeType,
      configuration: nil,
      URL: storeURL,
      options: self.config.options)
  }

  public lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(
      managedObjectModel: self.managedObjectModel)
    
    return persistentStoreCoordinator
    }()
  
  public lazy var managedObjectModel: NSManagedObjectModel = {
    if let modelName = self.config.modelName {
      let modelURL = NSBundle
        .mainBundle()
        .URLForResource(modelName, withExtension: "momd")!
      return NSManagedObjectModel(contentsOfURL: modelURL)!
    } else {
      return NSManagedObjectModel.mergedModelFromBundles(nil)!
    }
    }()

  public lazy var rootManagedObjectContext: NSManagedObjectContext = {
    let rootManagedObjectContext = self.createManagedObjectContext(.PrivateQueueConcurrencyType)
    rootManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    rootManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return rootManagedObjectContext
    }()

  public lazy var mainManagedObjectContext: NSManagedObjectContext = {
    let mainManagedObjectContext = self.createManagedObjectContext(.MainQueueConcurrencyType)
    mainManagedObjectContext.parentContext = self.rootManagedObjectContext
    mainManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return mainManagedObjectContext
    }()
  
  private lazy var applicationDocumentsDirectory: NSURL = {
    return NSFileManager
      .defaultManager()
      .URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] 
    }()

  private lazy var applicationBackupDirectory: NSURL = {
    let backupDirectory = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent("facade:backup")
    
    if !NSFileManager.defaultManager().fileExistsAtPath(backupDirectory.path!) {
      try! NSFileManager
        .defaultManager()
        .createDirectoryAtURL(
          backupDirectory,
          withIntermediateDirectories: false,
          attributes: nil)
    }
    
    return backupDirectory
    }()
}

// Singleton
extension Stack {

  class var sharedInstance: Stack {
    struct Singleton {
      static let instance = Stack()
    }
    return Singleton.instance
  }

}

// Notifications
extension Stack {

  private func registerForManagedObjectContextNotifications(managedObjectContext: NSManagedObjectContext) {
    NSNotificationCenter
      .defaultCenter()
      .addObserver(
        self,
        selector: "managedObjectContextDidSave:",
        name: NSManagedObjectContextDidSaveNotification,
        object: managedObjectContext)
  }
  
  private func unregisterForManagedObjectContextNotifications(managedObjectContext: NSManagedObjectContext? = nil) {
    NSNotificationCenter
      .defaultCenter()
      .removeObserver(
        self,
        name: NSManagedObjectContextDidSaveNotification,
        object: managedObjectContext)
  }
  
  @objc
  private func managedObjectContextDidSave(notification: NSNotification) {
    guard let savedManagedObjectContext = notification.object as? NSManagedObjectContext else {
      return
    }
    
    guard let parentManagedObjectContext = savedManagedObjectContext.parentContext else {
      return
    }
    
    if parentManagedObjectContext == rootManagedObjectContext {
      print("[managedObjectContextDidSave][CHILD] writing to disk (async)")
      commit(parentManagedObjectContext)
    } else {
      print("[managedObjectContextDidSave][CHILD] saving parent (sync)")
      commitSync(parentManagedObjectContext)
    }
    
    if independentManagedObjectContexts.contains(savedManagedObjectContext) {
      print("[managedObjectContextDidSave][INDEPENDENT] merging on other independent contexts")
      // Independent context
      for independentManagedObjectContext in independentManagedObjectContexts
        where independentManagedObjectContext != savedManagedObjectContext
      {
        independentManagedObjectContext.performBlockAndWait {
          independentManagedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
        }
      }
    }
  }

}

extension Stack {

  public var installed: Bool {
    let storePath = applicationDocumentsDirectory
      .URLByAppendingPathComponent("\(config.storeName!).sqlite")
      .path!
    
    return NSFileManager
      .defaultManager()
      .fileExistsAtPath(storePath)
  }
  
  public func backup() throws {
    for persistentStore in persistentStoreCoordinator.persistentStores {
      if let persistentStoreFileName = persistentStore.URL?.lastPathComponent {
        let storeBackupUrl = applicationBackupDirectory
          .URLByAppendingPathComponent("backup-\(persistentStoreFileName)")
        
        print("Backing up store to: \(storeBackupUrl)")
        
        try persistentStoreCoordinator.migratePersistentStore(
          persistentStore,
          toURL: storeBackupUrl,
          options: [
            NSSQLitePragmasOption: ["journal_mode": "DELETE"]
          ],
          withType: NSSQLiteStoreType)
      }
    }
  }

  public func drop() throws {
    print("Dropping database...")
    
    let fileManager = NSFileManager.defaultManager()
    
    for fileExtension in ["sqlite", "sqlite-shm", "sqlite-wal"] {
      let filePath = applicationDocumentsDirectory
        .URLByAppendingPathComponent("\(config.storeName!).\(fileExtension)")
        .path!
      
      if fileManager.fileExistsAtPath(filePath) {
        print("Dropping \(filePath)...")
        try fileManager.removeItemAtPath(filePath)
      }
    }
    
    print("Database successfuly droped.")
  }
  
  public func seed() throws {
    guard let storeName = config.storeName else {
      throw NSError(
        domain: "Store file name not defined. Use Facade.stack.config.seedName to define seed file",
        code: 1000,
        userInfo: nil)
    }

    guard let seedName = config.seedName else {
      throw NSError(
        domain: "Seed file name not defined. Use Facade.stack.config.seedName to define seed file",
        code: 1000,
        userInfo: nil)
    }
    
    guard let seedURL = NSBundle.mainBundle().URLForResource(seedName, withExtension: "sqlite") else {
      throw NSError(
        domain: "Seed file not found: \(seedName)",
        code: 1000,
        userInfo: nil)
    }

    let destinationURL = applicationDocumentsDirectory
      .URLByAppendingPathComponent("\(storeName).sqlite")

    print("Copying snapshot from \(seedURL) to \(destinationURL)")

    try NSFileManager
      .defaultManager()
      .copyItemAtURL(
        seedURL,
        toURL: destinationURL)
    
    print("Database successfuly seeded.")
  }

}