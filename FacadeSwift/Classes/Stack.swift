//
//  Stack.swift
//  Facade
//
//  Created by Olivier THIERRY on 30/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

open class Stack {

  open class Config {
    open var modelURL: URL!
    open var storeName: String! = Bundle.main.bundleIdentifier
    open var storeType: String = NSSQLiteStoreType
    open var seedURL: URL?
    open var modelPrimaryKey: String?
    open var options: [AnyHashable: Any] = [:]
  }

  open static let sharedInstance = Stack()

  open var config: Config = Config()
 
  fileprivate var managedObjectContexts: [String: NSManagedObjectContext] = [:]

  fileprivate var childManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.parent == self.mainManagedObjectContext }
      .map { $1 }
  }

  fileprivate var independentManagedObjectContexts: [NSManagedObjectContext] {
    return managedObjectContexts
      .filter { $1.parent == self.rootManagedObjectContext }
      .map { $1 }
    + [mainManagedObjectContext] // Include main context as independent
  }

  public init() {
  }
  
  deinit {
    unregisterForManagedObjectContextNotifications()
  }
  
  open func initialize() {
    registerForManagedObjectContextNotifications(mainManagedObjectContext)
    registerForManagedObjectContextNotifications(rootManagedObjectContext)
  }

  open lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(
      managedObjectModel: self.managedObjectModel)
    
    return persistentStoreCoordinator
  }()
  
  open lazy var managedObjectModel: NSManagedObjectModel = {
    if let modelURL = self.config.modelURL {
      print("Loading model from \(modelURL)")
      return NSManagedObjectModel(contentsOf: modelURL)!
    } else {
      print("Loading model by merging bundles []")
      return NSManagedObjectModel.mergedModel(from: nil)!
    }
  }()

  open lazy var rootManagedObjectContext: NSManagedObjectContext = {
    let rootManagedObjectContext = self.createManagedObjectContext(.privateQueueConcurrencyType)
    rootManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    rootManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return rootManagedObjectContext
  }()
  
  open lazy var mainManagedObjectContext: NSManagedObjectContext = {
    let mainManagedObjectContext = self.createManagedObjectContext(.mainQueueConcurrencyType)
    mainManagedObjectContext.parent = self.rootManagedObjectContext
    mainManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return mainManagedObjectContext
  }()
  
  fileprivate lazy var applicationDocumentsDirectory: URL = {
    return FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
  }()
  
  fileprivate lazy var applicationBackupDirectory: URL = {
    let backupDirectory = self
      .applicationDocumentsDirectory
      .appendingPathComponent("facade:backup")
    
    guard
      !FileManager.default.fileExists(atPath: backupDirectory.path)
      else { return backupDirectory }
    
    // Create backup directory
    try! FileManager.default
      .createDirectory(
        at: backupDirectory,
        withIntermediateDirectories: true,
        attributes: nil)
    
    return backupDirectory
  }()
}

// Managed object contexts management
extension Stack {

  public func createManagedObjectContext(_ concurrencyType: NSManagedObjectContextConcurrencyType) -> NSManagedObjectContext {
    return  NSManagedObjectContext(
      concurrencyType: concurrencyType)
  }
  
  public func registerChildContextWithIdentifier(
    _ identifier: String,
    parentManagedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext,
    concurrencyType: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType) -> NSManagedObjectContext
  {
    if let managedObjectContext = managedObjectContexts[identifier] {
      return managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parent = parentManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = managedObjectContext
    
    return managedObjectContext
  }
  
  public func registerIndependentContextWithIdentifier(
    _ identifier: String,
    concurrencyType: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType) -> NSManagedObjectContext
  {
    if let managedObjectContext = managedObjectContexts[identifier] {
      return managedObjectContext
    }
    
    let managedObjectContext = createManagedObjectContext(concurrencyType)
    managedObjectContext.parent = rootManagedObjectContext
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    
    registerForManagedObjectContextNotifications(managedObjectContext)
    managedObjectContexts[identifier] = managedObjectContext
    
    return managedObjectContext
  }
  
  public func unregisterContextWithIdentifier(_ identifier: String) {
    guard let managedObjectContext = managedObjectContexts[identifier] else {
      return
    }

    managedObjectContext.perform {
      managedObjectContext.reset()
      self.unregisterForManagedObjectContextNotifications(managedObjectContext)
    }

    // managedObjectContext is retained by performBlock's block
    // so we can remove it now
    self.managedObjectContexts.removeValue(forKey: identifier)
  }

  public func identifierForContext(_ managedObjectContext: NSManagedObjectContext) -> String? {
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
    _ managedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext,
    withCompletionHandler completionHandler: ((NSError?) -> Void)?)
  {
    let complete = { error in
      DispatchQueue.main.async {
        completionHandler?(error)
      }
    }
    
    managedObjectContext.perform {
      guard
        managedObjectContext.hasChanges
        else { return complete(nil) }
      
      do {
        try managedObjectContext.save()
        
        guard
          let parentManagedObjectContext = managedObjectContext.parent, parentManagedObjectContext != self.rootManagedObjectContext
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
    _ managedObjectContext: NSManagedObjectContext = Stack.sharedInstance.mainManagedObjectContext)
  {
    managedObjectContext.performAndWait {
      guard
        managedObjectContext.hasChanges
        else { return }
      
      do {
        try managedObjectContext.save()
        managedObjectContext.processPendingChanges()
        
        if let parentManagedObjectContext = managedObjectContext.parent, parentManagedObjectContext != self.rootManagedObjectContext
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

  fileprivate func registerForManagedObjectContextNotifications(_ managedObjectContext: NSManagedObjectContext) {
    NotificationCenter.default
      .addObserver(
        self,
        selector: #selector(managedObjectContextDidSave),
        name: NSNotification.Name.NSManagedObjectContextDidSave,
        object: managedObjectContext)
  }
  
  fileprivate func unregisterForManagedObjectContextNotifications(_ managedObjectContext: NSManagedObjectContext? = nil) {
    NotificationCenter.default
      .removeObserver(
        self,
        name: NSNotification.Name.NSManagedObjectContextDidSave,
        object: managedObjectContext)
  }

  @objc
  fileprivate func managedObjectContextDidSave(_ notification: Notification) {
    guard
      let savedManagedObjectContext = notification.object as? NSManagedObjectContext
      else { return }

    // Break retain cycles and release memory
    savedManagedObjectContext.perform {
      savedManagedObjectContext.refreshAllObjects()
    }

    guard
      savedManagedObjectContext.parent == self.rootManagedObjectContext
      else { return }

    // Independent context
    for independentManagedObjectContext in independentManagedObjectContexts
      where independentManagedObjectContext != savedManagedObjectContext
    {
      independentManagedObjectContext.perform {
        // NSManagedObjectContext's merge routine ignores updated objects which aren't
        // currently faulted in. To force it to notify interested clients that such
        // objects have been refreshed (e.g. NSFetchedResultsController) we need to
        // force them to be faulted in ahead of the merge
        // SEE: http://mikeabdullah.net/merging-saved-changes-betwe.html
        if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
          for updatedObject in updatedObjects {
            let _ = try? independentManagedObjectContext.existingObject(with: updatedObject.objectID)
          }
        }

        // Merge changes on the idependent context
        independentManagedObjectContext.mergeChanges(
          fromContextDidSave: notification)

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
      .appendingPathComponent("\(self.config.storeName!).sqlite")
      .path
    
    return FileManager.default
      .fileExists(atPath: storePath)
  }

  public func connect() throws {
    let storeURL = self.applicationDocumentsDirectory
      .appendingPathComponent(self.config.storeName!)
      .appendingPathExtension("sqlite")
    
    try persistentStoreCoordinator.addPersistentStore(
      ofType: self.config.storeType,
      configurationName: nil,
      at: storeURL,
      options: self.config.options)
  }

  public func backup() throws {
    for persistentStore in persistentStoreCoordinator.persistentStores {
      if let persistentStoreFileName = persistentStore.url?.lastPathComponent {
        let storeBackupUrl = applicationBackupDirectory
          .appendingPathComponent("backup-\(persistentStoreFileName)")
        
        print("Backing up store to: \(storeBackupUrl)")
        
        try persistentStoreCoordinator.migratePersistentStore(
          persistentStore,
          to: storeBackupUrl,
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
    
    let fileManager = FileManager.default
    
    for fileExtension in ["sqlite", "sqlite-shm", "sqlite-wal"] {
      let filePath = applicationDocumentsDirectory
        .appendingPathComponent("\(self.config.storeName!).\(fileExtension)")
        .path
      
      if fileManager.fileExists(atPath: filePath) {
        print("Dropping \(filePath)...")
        try fileManager.removeItem(atPath: filePath)
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
        domain: "Seed file not found: \(String(describing: self.config.seedURL))",
        code: 1000,
        userInfo: nil)
    }

    let destinationURL = applicationDocumentsDirectory
      .appendingPathComponent("\(storeName).sqlite")

    print("Copying snapshot from \(seedURL) to \(destinationURL)")

    try FileManager.default
      .copyItem(
        at: seedURL,
        to: destinationURL)
    
    print("Database successfuly seeded.")
  }

}

public var facade_stack: Facade.Stack {
  return Stack.sharedInstance
}
