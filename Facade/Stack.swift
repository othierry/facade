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
  
  public func commit(_ managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext) {
    managedObjectContext.performBlock {
      println("commit \(managedObjectContext)")
      var error: NSError?
      if managedObjectContext.hasChanges && !managedObjectContext.save(&error) {
        if let error = error {
          println("[Facade.stack.commit] Error saving context \(managedObjectContext). Error: \(error)")
        }
      }
    }
  }
  
  public func commitSync(_ managedObjectContext: NSManagedObjectContext = Facade.stack.mainManagedObjectContext) {
    managedObjectContext.performBlockAndWait {
      println("commitSync \(managedObjectContext)")
      var error: NSError?
      if managedObjectContext.hasChanges && !managedObjectContext.save(&error) {
        if let error = error {
          println("[Facade.stack.commitSync] Error saving context \(managedObjectContext). Error: \(error)")
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
  
  public func connect() -> Bool {
    let storeURL = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent(self.config.storeName!)
      .URLByAppendingPathExtension("sqlite")
    
    var error: NSError? = nil
    
    println("Connecting to \(storeURL)")
    
    let persistentStore = persistentStoreCoordinator.addPersistentStoreWithType(
      self.config.storeType,
      configuration: nil,
      URL: storeURL,
      options: self.config.options,
      error: &error)
    
    return persistentStore != nil
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
    println("mainManagedObjectContext")
    let rootManagedObjectContext = self.createManagedObjectContext(.PrivateQueueConcurrencyType)
    rootManagedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    rootManagedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return rootManagedObjectContext
    }()

  public lazy var mainManagedObjectContext: NSManagedObjectContext = {
    println("mainManagedObjectContext")
    let mainManagedObjectContext = self.createManagedObjectContext(.MainQueueConcurrencyType)
    mainManagedObjectContext.parentContext = self.rootManagedObjectContext
    return mainManagedObjectContext
    }()
  
  private lazy var applicationDocumentsDirectory: NSURL = {
    return NSFileManager
      .defaultManager()
      .URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] as! NSURL
    }()

  private lazy var applicationBackupDirectory: NSURL = {
    let backupDirectory = self.applicationDocumentsDirectory
      .URLByAppendingPathComponent("backup")
    
    if !NSFileManager.defaultManager().fileExistsAtPath(backupDirectory.path!) {
      NSFileManager
        .defaultManager()
        .createDirectoryAtURL(
          backupDirectory,
          withIntermediateDirectories: false,
          attributes: nil,
          error: nil)
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
  
  private func unregisterForManagedObjectContextNotifications(_ managedObjectContext: NSManagedObjectContext? = nil) {
    NSNotificationCenter
      .defaultCenter()
      .removeObserver(
        self,
        name: NSManagedObjectContextDidSaveNotification,
        object: managedObjectContext)
  }
  
  @objc
  private func managedObjectContextDidSave(notification: NSNotification) {
    println("managedObjectContextDidSave")
    
    if let savedContext = notification.object as? NSManagedObjectContext {
      if savedContext == mainManagedObjectContext {
        println("write to disk")
        // Write to disk
        commit(rootManagedObjectContext)
      } else {
        println("merging on children")
        // Propagate changes on childrens
        for (identifier, context) in childManagedObjectContexts {
          println("checking \(identifier)")
          if context != savedContext {
            println("merge on \(identifier)")
            context.mergeChangesFromContextDidSaveNotification(notification)
          }
        }
      }
    }
  }

}

extension Stack {

  public func backup() {
    for persistentStore in persistentStoreCoordinator.persistentStores as! [NSPersistentStore] {
      if let persistentStoreFileName = persistentStore.URL?.lastPathComponent {
        let storeBackupUrl = applicationBackupDirectory
          .URLByAppendingPathComponent("backup-\(persistentStoreFileName)")
        
        println("Backing up store from \(persistentStore.URL!) to \(storeBackupUrl)")
        
        persistentStoreCoordinator.migratePersistentStore(
          persistentStore,
          toURL: storeBackupUrl,
          options: [
            NSSQLitePragmasOption: ["journal_mode": "DELETE"]
          ],
          withType: NSSQLiteStoreType,
          error: nil)
      }
    }
  }
  
//  public func restore() -> Bool {
//    let backupStoreURL = NSBundle
//      .mainBundle()
//      .URLForResource(
//        "backup-\(config.storeName!)",
//        withExtension: "sqlite")
//
//    if let backupStoreURL = backupStoreURL  {
//       let persistentStore = persistentStoreCoordinator.addPersistentStoreWithType(
//        NSSQLiteStoreType,
//        configuration: nil,
//        URL: backupStoreURL,
//        options: [NSReadOnlyPersistentStoreOption: true],
//        error: nil)
//
//      let destinationURL = applicationDocumentsDirectory.URLByAppendingPathComponent("\(config.storeName!).sqlite")
//
//      if let persistentStore = persistentStore {
//        println("Restoring store from \(backupStoreURL) to \(destinationURL)")
//
//        let migratedPersistentStore = persistentStoreCoordinator.migratePersistentStore(
//          persistentStore,
//          toURL: destinationURL,
//          options: nil,
//          withType: NSSQLiteStoreType,
//          error: nil)
//
//        return migratedPersistentStore != nil
//      }
//    }
//
//    return false
//  }

  public func restore() -> Bool {
    let backupStoreURL = NSBundle
      .mainBundle()
      .URLForResource(
        "backup-\(config.storeName!)",
        withExtension: "sqlite")
    
    if let backupStoreURL = backupStoreURL  {
      let destinationURL = applicationDocumentsDirectory
        .URLByAppendingPathComponent("\(config.storeName!).sqlite")

      return NSFileManager
        .defaultManager()
        .copyItemAtURL(
          backupStoreURL,
          toURL: destinationURL,
          error: nil)
    }
    
    return false
  }

}