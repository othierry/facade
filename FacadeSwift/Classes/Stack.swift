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
    public var modelURL: NSURL!
    public var storeName: String! = NSBundle.mainBundle().bundleIdentifier
    public var storeType: String = NSSQLiteStoreType
    public var seedURL: NSURL?
    public var modelPrimaryKey: String?
    public var options: [NSObject : AnyObject] = [:]
  }

  public static let sharedInstance = Stack()

  public var config: Config = Config()
 
  private var managedObjectContexts: [String: NSManagedObjectContext] = [:]

  private var childManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.parentContext == self.mainManagedObjectContext }
      .map { $1 }
  }

  private var independentManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.parentContext == self.rootManagedObjectContext }
      .map { $1 }
    + [mainManagedObjectContext] // Include main context as independent
  }

  public init() {
  }
  
  deinit {
    unregisterForManagedObjectContextNotifications()
  }
  
  public func initialize() {
    registerForManagedObjectContextNotifications(mainManagedObjectContext)
    registerForManagedObjectContextNotifications(rootManagedObjectContext)
  }

  public lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(
      managedObjectModel: self.managedObjectModel)
    
    return persistentStoreCoordinator
  }()
  
  public lazy var managedObjectModel: NSManagedObjectModel = {
    if let modelURL = self.config.modelURL {
      print("Loading model from \(modelURL)")
      return NSManagedObjectModel(contentsOfURL: modelURL)!
    } else {
      print("Loading model by merging bundles []")
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
    
    guard
      !NSFileManager.defaultManager().fileExistsAtPath(backupDirectory!.path!)
      else { return backupDirectory! }
    
    // Create backup directory
    try! NSFileManager
      .defaultManager()
      .createDirectoryAtURL(
        backupDirectory!,
        withIntermediateDirectories: true,
        attributes: nil)
    
    return backupDirectory!
  }()
}

// Managed object contexts management
extension Stack {

  public func createManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType) -> NSManagedObjectContext {
    return  NSManagedObjectContext(
      concurrencyType: concurrencyType)
  }
  
  public func registerChildContextWithIdentifier(
    identifier: String,
    parentManagedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext,
    concurrencyType: NSManagedObjectContextConcurrencyType = .PrivateQueueConcurrencyType) -> NSManagedObjectContext
  {
    if let managedObjectContext = managedObjectContexts[identifier] {
      return managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parentContext = parentManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = managedObjectContext
    
    return managedObjectContext
  }
  
  public func registerIndependentContextWithIdentifier(
    identifier: String,
    concurrencyType: NSManagedObjectContextConcurrencyType = .PrivateQueueConcurrencyType) -> NSManagedObjectContext
  {
    if let managedObjectContext = managedObjectContexts[identifier] {
      return managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parentContext = rootManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    
    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = managedObjectContext
    
    return managedObjectContext
  }
  
  public func unregisterContextWithIdentifier(identifier: String) {
    guard let managedObjectContext = managedObjectContexts[identifier] else {
      return
    }

    managedObjectContext.performBlock {
      managedObjectContext.reset()
      self.unregisterForManagedObjectContextNotifications(managedObjectContext)
    }

    // managedObjectContext is retained by performBlock's block
    // so we can remove it now
    self.managedObjectContexts.removeValueForKey(identifier)
  }

  public func identifierForContext(managedObjectContext: NSManagedObjectContext) -> String? {
    for (identifier, context) in managedObjectContexts {
      if context === managedObjectContext {
        return identifier
      }
    }
    
    return nil
  }

}

// Persistence
extension Stack {
  
  public func commit(
    managedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext,
    withCompletionHandler completionHandler: (NSError? -> Void)?)
  {
    let complete = { error in
      dispatch_async(dispatch_get_main_queue()) {
        completionHandler?(error)
      }
    }
    
    managedObjectContext.performBlock {
      guard
        managedObjectContext.hasChanges
        else { return complete(nil) }
      
      do {
        try managedObjectContext.save()
        
        guard
          let parentManagedObjectContext = managedObjectContext.parentContext
          where parentManagedObjectContext != self.rootManagedObjectContext
          else { return complete(nil) }
        
        self.commit(
          parentManagedObjectContext,
          withCompletionHandler: completionHandler)
      } catch let error as NSError {
        print("[Stack.sharedInstance.commit] Error saving context \(managedObjectContext). Error: \(error)")
        complete(error)
      }
    }
  }
  
  public func commitSync(
    managedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext)
  {
    managedObjectContext.performBlockAndWait {
      guard
        managedObjectContext.hasChanges
        else { return }
      
      do {
        try managedObjectContext.save()
        managedObjectContext.processPendingChanges()
        
        if let parentManagedObjectContext = managedObjectContext.parentContext
          where parentManagedObjectContext != self.rootManagedObjectContext
        {
          self.commitSync(parentManagedObjectContext)
        }
      } catch let error as NSError {
        print("[Stack.sharedInstance.commitSync] Error saving context \(managedObjectContext). Error: \(error)")
      }
    }
  }
  
}

// Notifications & Merging
extension Stack {

  private func registerForManagedObjectContextNotifications(managedObjectContext: NSManagedObjectContext) {
    NSNotificationCenter
      .defaultCenter()
      .addObserver(
        self,
        selector: #selector(managedObjectContextDidSave),
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
    guard
      let savedManagedObjectContext = notification.object as? NSManagedObjectContext
      else { return }

    // Break retain cycles and release memory
    savedManagedObjectContext.performBlock {
      savedManagedObjectContext.refreshAllObjects()
    }

    guard
      savedManagedObjectContext.parentContext == self.rootManagedObjectContext
      else { return }

    // Independent context
    for independentManagedObjectContext in independentManagedObjectContexts
      where independentManagedObjectContext != savedManagedObjectContext
    {
      independentManagedObjectContext.performBlock {
        // NSManagedObjectContext's merge routine ignores updated objects which aren't
        // currently faulted in. To force it to notify interested clients that such
        // objects have been refreshed (e.g. NSFetchedResultsController) we need to
        // force them to be faulted in ahead of the merge
        // SEE: http://mikeabdullah.net/merging-saved-changes-betwe.html
        if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
          for updatedObject in updatedObjects {
            let _ = try? independentManagedObjectContext.existingObjectWithID(updatedObject.objectID)
          }
        }

        // Merge changes on the idependent context
        independentManagedObjectContext.mergeChangesFromContextDidSaveNotification(
          notification)

        // Break retain cycles, release unnessecary memory
        // after the merge occurs
        independentManagedObjectContext.refreshAllObjects()
      }
    }

    print("[Facade] Write to disk...")

    // Write to disk
    commit(self.rootManagedObjectContext, withCompletionHandler: nil)
  }

}

// Connect, backup & seed APIs
extension Stack {

  public var installed: Bool {
    let storePath = applicationDocumentsDirectory
      .URLByAppendingPathComponent("\(self.config.storeName!).sqlite")!
      .path!
    
    return NSFileManager
      .defaultManager()
      .fileExistsAtPath(storePath)
  }

  public func connect() throws {
    let storeURL = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent(self.config.storeName!)!
      .URLByAppendingPathExtension("sqlite")
    
    try persistentStoreCoordinator.addPersistentStoreWithType(
      self.config.storeType,
      configuration: nil,
      URL: storeURL,
      options: self.config.options)
  }

  public func backup() throws {
    for persistentStore in persistentStoreCoordinator.persistentStores {
      if let persistentStoreFileName = persistentStore.URL?.lastPathComponent {
        let storeBackupUrl = applicationBackupDirectory
          .URLByAppendingPathComponent("backup-\(persistentStoreFileName)")
        
        print("Backing up store to: \(storeBackupUrl)")
        
        try persistentStoreCoordinator.migratePersistentStore(
          persistentStore,
          toURL: storeBackupUrl!,
          options: [
            NSSQLitePragmasOption: ["journal_mode": "DELETE"],
            NSSQLiteManualVacuumOption: true
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
        .URLByAppendingPathComponent("\(self.config.storeName!).\(fileExtension)")!
        .path!
      
      if fileManager.fileExistsAtPath(filePath) {
        print("Dropping \(filePath)...")
        try fileManager.removeItemAtPath(filePath)
      }
    }
    
    print("Database successfuly droped.")
  }
  
  public func seed() throws {
    guard let storeName = self.config.storeName else {
      throw NSError(
        domain: "Store file name not defined. Use Stack.sharedInstance.config.seedName to define seed file",
        code: 1000,
        userInfo: nil)
    }

    guard let seedURL = self.config.seedURL else {
      throw NSError(
        domain: "Seed file not found: \(self.config.seedURL)",
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
        toURL: destinationURL!)
    
    print("Database successfuly seeded.")
  }

}

public var facade_stack: Facade.Stack {
  return Stack.sharedInstance
}
