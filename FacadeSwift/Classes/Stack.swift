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
  
  public static let sharedInstance = Stack()
  
  public class Config {
    public static let sharedConfig = Config()
    
    public var modelURL: NSURL!
    public var storeName: String! = NSBundle.mainBundle().bundleIdentifier
    public var storeType: String = NSSQLiteStoreType
    public var seedURL: NSURL?
    public var modelPrimaryKey: String?
    public var options: [NSObject : AnyObject] = [:]
  }
 
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
    registerForManagedObjectContextNotifications(mainManagedObjectContext)
    registerForManagedObjectContextNotifications(rootManagedObjectContext)
  }
  
  deinit {
    unregisterForManagedObjectContextNotifications()
  }

  public lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(
      managedObjectModel: self.managedObjectModel)
    
    return persistentStoreCoordinator
  }()
  
  public lazy var managedObjectModel: NSManagedObjectModel = {
    if let modelURL = Config.sharedConfig.modelURL {
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
      !NSFileManager.defaultManager().fileExistsAtPath(backupDirectory.path!)
      else { return backupDirectory }
    
    // Create backup directory
    try! NSFileManager
      .defaultManager()
      .createDirectoryAtURL(
        backupDirectory,
        withIntermediateDirectories: true,
        attributes: nil)
    
    return backupDirectory
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
    // on the saved context
    savedManagedObjectContext.performBlock(
      savedManagedObjectContext.refreshAllObjects)

    guard
      savedManagedObjectContext == self.rootManagedObjectContext
      else
    {
      // Write to disk
      print("[Facade] Write to disk...")
      commit(self.rootManagedObjectContext, withCompletionHandler: nil)
      return
    }

    // Independent context
    for independentManagedObjectContext in independentManagedObjectContexts {
      independentManagedObjectContext.performBlock {
        independentManagedObjectContext
          .mergeChangesFromContextDidSaveNotification(notification)
      }
    }
  }

}

// Connect, backup & seed APIs
extension Stack {

  public var installed: Bool {
    let storePath = applicationDocumentsDirectory
      .URLByAppendingPathComponent("\(Config.sharedConfig.storeName!).sqlite")
      .path!
    
    return NSFileManager
      .defaultManager()
      .fileExistsAtPath(storePath)
  }

  public func connect() throws {
    let storeURL = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent(Config.sharedConfig.storeName!)
      .URLByAppendingPathExtension("sqlite")
    
    try persistentStoreCoordinator.addPersistentStoreWithType(
      Config.sharedConfig.storeType,
      configuration: nil,
      URL: storeURL,
      options: Config.sharedConfig.options)
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
        .URLByAppendingPathComponent("\(Config.sharedConfig.storeName!).\(fileExtension)")
        .path!
      
      if fileManager.fileExistsAtPath(filePath) {
        print("Dropping \(filePath)...")
        try fileManager.removeItemAtPath(filePath)
      }
    }
    
    print("Database successfuly droped.")
  }
  
  public func seed() throws {
    guard let storeName = Config.sharedConfig.storeName else {
      throw NSError(
        domain: "Store file name not defined. Use Stack.sharedInstance.config.seedName to define seed file",
        code: 1000,
        userInfo: nil)
    }

    guard let seedURL = Config.sharedConfig.seedURL else {
      throw NSError(
        domain: "Seed file not found: \(Config.sharedConfig.seedURL)",
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