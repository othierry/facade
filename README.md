# FacadeSwift

[![CI Status](http://img.shields.io/travis/Olivier Thierry/FacadeSwift.svg?style=flat)](https://travis-ci.org/Olivier Thierry/FacadeSwift)
[![Version](https://img.shields.io/cocoapods/v/FacadeSwift.svg?style=flat)](http://cocoapods.org/pods/FacadeSwift)
[![License](https://img.shields.io/cocoapods/l/FacadeSwift.svg?style=flat)](http://cocoapods.org/pods/FacadeSwift)
[![Platform](https://img.shields.io/cocoapods/p/FacadeSwift.svg?style=flat)](http://cocoapods.org/pods/FacadeSwift)

## Introduction

**DOCUMENTATION IN PROGRESS**

`Facade` acts as a facade between your app and `CoreData`. It makes configuration and usage a lot easier, provides flexible parent-child architecture and powerful querying APIs.

`Facade.Stack` builds an optimized `Parent/Child` stack architecture that allows efficient read and asynchronous write operations for persistence phase along with detached transactions.

## Installation

FacadeSwift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "FacadeSwift"
```

## Usage

### Setup

```swift
facade_stack.config.storeName = "MyApp"
facade_stack.connect()
```

That's all you need to do to start using `Facade`. More deeper configuration and usage, see the documentation bellow.

### Using a data seed

You can use a seed when setting up your database for the first time.

```swift
facade_stack.config.seedURL = NSBundle.mainBundle()
  .URLForResource(
    "myseed",
    withExtension: "sqlite")

// Install the seed
try! facade_stack.seed()
try! facade_stack.connect()
```

### Droping database

```swift
// Check that database exists before trying to drop it
if facade_stack.installed {
  try! facade_stack.drop()
}
```

### Using a different datamodel schema

If your datamodel schema is not in your main bundle (in a framework or resource bundle), you will have to provide the URL so that CoreData can fetch it.

```swift
facade_stack.config.modelURL = myBundle
  .URLForResource(
    "MyAppDataModel",
    withExtension: "momd")
```

### Using CoreData built-in options

Of course you can use CoreData built-in options by using the attribute `options` of the shared `Config`

```swift
facade_stack.config.options[NSMigratePersistentStoresAutomaticallyOption] = true
facade_stack.config.options[NSInferMappingModelAutomaticallyOption] = true
```

### Connecting to the database

**After** the configuration phase, you must establish a connection to the database. This operation adds the persistent store to the persistent store coordinator.

```
try! facade_stack.connect()
```

## Query API

The Query API is flexible and powerful. You don't need to take care of the backend of `NSFetchRequest` or `SQLite` or anything. You can just use high level APIs and focus of the functional part of your app.

### Query options

- Matching options
  - `CaseInsensitive`
  - `DiacriticInsensitive`

- Customizing query
  - `limit(_:)`: *Documentation in progress*
  - `offset(_:)`: *Documentation in progress*
  - `fetchBatchSize(_:)`: *Documentation in progress*
  - `prefetch(_:)`: *Documentation in progress*
  - `faults(_:)`: *Documentation in progress*
  - `groupBy(_:)`: *Documentation in progress*
  - `refresh(_:)`: *Documentation in progress*

### Choosing query managed object context

By default, a request always executes in `facade_stack.mainManagedObjectContext`. You can override this behaviour by giving the context is which the query must execute.

```
let user = facade_query(User)
  .inManagedObjectContext(myCustomContext)
  .first()
```

### Predicates

### with(\_:equalTo:options:) / with(\_:notEqualTo:options:)

```swift
let recipes = facade_query(Recipe)
  .with("difficulty", equalTo: 3)
  .all()
```

```swift
let users = facade_query(User)
  .with(
    "firstname",
    notEqualTo: "olivier",
    options: [
      .CaseInsensitive,
      .DiacriticInsensitive])
  .all()
```

### with(\_:containedIn:) / with(\_:notContainedIn:)

```swift
let user = facade_query(User)
  .with(
    "email",
    containedIn: [
      "olivier@save.co",
      "olivier.thierry42@gmail.com"])
  .first()
```

```swift
let roles = facade_query(Role)
  .limit(2)
  .all()

let users = facade_query(User)
  .with(
    "role",
    notContainedIn: roles)
  .all()
```

### with(\_:containingAll:) / with(\_:containingNone:) / with(\_:containingAny:)

```swift
let recipes = facade_query(Recipe)
  .with("ingredients", containingAll: listOfAvailableIngredients)
  .all()
```

```swift
let recipes = facade_query(Recipe)
  .with("ingredients", containingAny: listOfAvailableIngredients)
  .all()
```

```swift
let recipes = facade_query(Recipe)
  .with("ingredients", containingNone: listOfAvailableIngredients)
  .all()
```

### with(\_:containing:options:) / with(\_:like:options:)

```swift
let users = facade_query(User)
  .with(
    "firstname",
    containing: "liv")
  .all()
```

```swift
let users = facade_query(User)
  .with(
    "firstname",
    like: "oliv%",
    options: [.CaseInsensitive])
  .all()
```

### with(\_:existing:)

Predicate to match property that exists (`!= nil`) or don't exists (`== nil`)

```swift
let usersWithoutEmail = facade_query(User)
  .with("email", existing: false)
  .all()
```

### with(\_:startingWith:options:) / with(\_:endingWith:options:)

These functions are syntatic functions for `LIKE pattern%` and `LIKE %pattern`

```swift
let users = facade_query(User)
  .with("email", endingWith: "@gmail.com")
  .all()
```

### with(\_:greaterThan:) / with(\_:greaterThanOrEqual:) / with(\_:lowerThan:) / with(\_:lowerThanOrEqual:)

```swift
let users = facade_query(User)
  .with("age", greaterThanOrEqual: 18)
  .all()
```

## .or()

```swift
let recipes = facade_queryOr([
    // Vegan AND difficulty maximum (5)
    facade_query(Recipe)
      .with("difficulty", equalTo: 5)
      .with("vegan", equalTo: true),
    // Non-vegan AND difficulty between 3-5
    facade_query(Recipe)
      .with("difficulty", greaterThanOrEqualTo: 3)
      .with("vegan", equalTo: false)
  ])
  // In both case, we want recipes to take less than 30 mins to cook
  .with("time", lessThanOrEqualTo: 30)
  .sort("difficulty")
  .all()
```

## Sorting results

By default, using `sort(_:)` will sort results in ascending order.

```swift
facade_query(User)
  .sort("email")
  .all()

// Is exactly the same as

facade_query(User)
  .sort("email ASC")
  .all()
```

You can add `DESC` or `desc` (case insensitive) to your sort predidcate to change sorting order,

```swift
facade_query(User)
  .sort("email DESC")
  .all()
```

## Delete / Batch deletes

You can directly delete/batch delete matching results from the query object

```swift
facade_query(Recipe)
  .with("favorite", equalTo: false)
  .delete()
```

```swift
facade_query(Recipe)
  .with("favorite", equalTo: false)
  .batchDelete() // Async delete using NSBatchDeleteRequest
```

## all() VS. execute() VS count()

There's 3 ways to execute a query.
- `count()` will as its name says, returns a simple count of matching entities.
- `all()` will always return an array of [A] where A is your entity type.
- `execute()` has 3 signatures
 - `execute() -> [A]`: Behaves the same way as `all()`
 - `execute() -> [NSManagedObjectID]`: Will set the result type of the fetch request to `.ManagedObjectIDResultType` and returns an array of `NSManagedObjectID`s.
 - `execute() -> [NSDictionary]`: Will set the result type of the fetch request to `.DictionaryResultType` and returns a raw representation of the objects as instances of `NSDictionary`s

 On most case, I just use `execute()` and let the compiler infer the type I am waiting for, which it is pretty good at <3.

## first() & last()

In some case, you want to fetch the first or last object matching your query. By default, `first()` and `last()` will behave exactly the same. By default, this means that `query.first() === query.last()`. Because those 2 methods set a limit of 1 and sort the results set by `facade_stack.config.modelPrimaryKey` which will have no effect if you did not set it in first place.

During your stack configuration. Add the following

```swift
facade_stack.config.modelPrimaryKey = "id"
```

From now on, `query.first() != query.last()` (unless of course `query.count() <= 1`) as `Facade` will detect the default primary key and sort the result accordingly.

## Facade.Query to NSFetchedResultsController

*Documentation in progress*

## Elastic Query

*Documentation in progress*

## Transactions

*Documentation in progress*

## Operators

- `<->`: *Documentation in progress*
- `<=>`: *Documentation in progress*
- `</>`: *Documentation in progress*
- `<-`: *Documentation in progress*

## Author

Olivier Thierry, olivier.thierry42@gmail.com

## License

FacadeSwift is available under the MIT license. See the LICENSE file for more info.
