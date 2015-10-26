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
  
  public private(set) var config = Config()
  private var childManagedObjectContexts: [String : NSManagedObjectContext] = [:]
  
  private init() {
    registerForManagedObjectContextNotifications(mainManagedObjectContext)
  }
  
  deinit {
    unregisterForManagedObjectContextNotifications()
  }
  
  public func commit(managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext) {
    managedObjectContext.performBlock {
      if managedObjectContext.hasChanges {
        do {
          try managedObjectContext.save()
        } catch let error as NSError {
          print("[Facade.stack.commit] Error saving context \(managedObjectContext). Error: \(error)")
        } catch {
          fatalError()
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
        } catch {
          fatalError()
        }
      }
    }
  }
  
  public func createManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType) -> NSManagedObjectContext {
    let managedObjectContext = NSManagedObjectContext(
      concurrencyType: concurrencyType)
    return managedObjectContext
  }

  public func registerChildContextWithIdentifier(identifier: String) -> NSManagedObjectContext {
    if childManagedObjectContexts[identifier] == nil {
      let managedObjectContext = createManagedObjectContext(.PrivateQueueConcurrencyType)
      managedObjectContext.parentContext = mainManagedObjectContext
      registerForManagedObjectContextNotifications(managedObjectContext)
      childManagedObjectContexts[identifier] = managedObjectContext
    }
    
    return childManagedObjectContexts[identifier]!
  }

  public func unregisterChildContextWithIdentifier(identifier: String) {
    if let managedObjectContext = childManagedObjectContexts[identifier] {
      unregisterForManagedObjectContextNotifications(managedObjectContext)
      managedObjectContext.reset()
      childManagedObjectContexts.removeValueForKey(identifier)
    }
  }
  
  public func identifierForChildContext(managedObjectContext: NSManagedObjectContext) -> String? {
    for (identifier, context) in childManagedObjectContexts {
      if context === managedObjectContext {
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
    return mainManagedObjectContext
    }()
  
  private lazy var applicationDocumentsDirectory: NSURL = {
    return NSFileManager
      .defaultManager()
      .URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] 
    }()

  private lazy var applicationBackupDirectory: NSURL = {
    let backupDirectory = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent("backup")
    
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
    print("managedObjectContextDidSave")
    
    if let savedContext = notification.object as? NSManagedObjectContext {
      if savedContext == mainManagedObjectContext {
        print("write to disk")
        // Write to disk
        commit(rootManagedObjectContext)
      } else {
        print("merging on children")
        // Propagate changes on childrens
        for (identifier, context) in childManagedObjectContexts {
          print("checking \(identifier)")
          if context != savedContext {
            print("merge on \(identifier)")
            context.mergeChangesFromContextDidSaveNotification(notification)
          }
        }
      }
    }
  }

}

extension Stack {

  public func backup() throws {
    for persistentStore in persistentStoreCoordinator.persistentStores {
      if let persistentStoreFileName = persistentStore.URL?.lastPathComponent {
        let storeBackupUrl = applicationBackupDirectory
          .URLByAppendingPathComponent("backup-\(persistentStoreFileName)")
        
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

  public func restore() throws {
    let backupStoreURL = NSBundle
      .mainBundle()
      .URLForResource(
        "backup-\(config.storeName!)",
        withExtension: "sqlite")
    
    guard let _ = backupStoreURL else {
      throw NSError(domain: "File not found", code: NSFileNoSuchFileError, userInfo: nil)
    }
    
    let destinationURL = applicationDocumentsDirectory
      .URLByAppendingPathComponent("\(config.storeName!).sqlite")
    
    try NSFileManager
      .defaultManager()
      .copyItemAtURL(
        backupStoreURL!,
        toURL: destinationURL)
  }

}