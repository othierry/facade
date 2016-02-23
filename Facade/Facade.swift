//
//  Facade.swift
//  Save
//
//  Created by Olivier THIERRY on 04/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation
import CoreData

public class Facade {
  
  public static var stack = Stack()
  
  public static func query<A: NSManagedObject>(type: A.Type) -> Query<A> {
    return Query<A>()
  }
  
}
