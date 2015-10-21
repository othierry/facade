//
//  FacadeTests.swift
//  FacadeTests
//
//  Created by Olivier THIERRY on 24/05/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import UIKit
import XCTest
import CoreData

class Test: NSManagedObject {}

class FacadeTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testExample() {
    let q = Test.query()
    // This is an example of a functional test case.
    XCTAssert(true, "Pass")
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock() {
      // Put the code you want to measure the time of here.
    }
  }
  
}
