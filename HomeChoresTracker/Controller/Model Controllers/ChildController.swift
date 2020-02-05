import Foundation
import CoreData

class ChildController {
    private let loginURL = URL(string: "https://chore-tracker1.herokuapp.com/api/auth/login/child")
    private let choreURL = URL(string: "https://chore-tracker1.herokuapp.com/api/auth/child")
    var bearer: Bearer?
    var child: Child?
    var chores = [ChoreRepresentation]()
    let networkLoader: NetworkDataLoader
    
    init(networkLoader: NetworkDataLoader = URLSession.shared) {
        self.networkLoader = networkLoader
    }
    
    //MARK: Auth
    func login(with username: String, and password: String, complete: @escaping NetworkService.CompletionWithError = {error in}) {
        guard let request = createRequestAndEncodeUser(user: User(username: username, password: password), url: loginURL, method: .post, headerType: .contentType, headerValue: .json) else {
            let error = NSError(domain: "ChildController.login.requestError", code: NetworkService.NetworkError.badRequest.rawValue)
            complete(error)
            return
        }
        
        networkLoader.loadData(using: request) { (data, response, error) in
            if let response = response,
                response.statusCode != 200 {
                print("bad response code")
                DispatchQueue.main.async {
                    complete(NSError(domain: "ChildController.login.response.statusCode", code: response.statusCode, userInfo: nil))
                }
                return
            }
            if let error = error {
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            
            guard let data = data else {
                print("no data")
                DispatchQueue.main.async {
                    complete(NSError())
                }
                return
            }
            
            guard let bearer = NetworkService.decode(to: Bearer.self, data: data) as? Bearer else {
                let error = NSError(domain: "ChildController.loginChild.decodeBearer", code: NetworkService.NetworkError.badDecode.rawValue)
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            self.bearer = bearer
            DispatchQueue.main.async {
                complete(nil)
            }
        }
    }
    
    //MARK: Read
    /**
     Get a child from the API - currently unused
     */
    func getChild(complete: @escaping NetworkService.CompletionWithError  = {error in}) {
        guard var request = NetworkService.createRequest(url: choreURL, method: .get, headerType: .contentType, headerValue: .json) else {
            let error = NSError(domain: "ChildController.getChild.requestError", code: NetworkService.NetworkError.badRequest.rawValue)
            complete(error)
            return
        }
        guard let bearer = bearer else {
            let error = NSError(domain: "ChildController.bearer", code: NetworkService.NetworkError.unauth.rawValue)
            complete(error)
            return
        }
        request.setValue(bearer.token, forHTTPHeaderField: NetworkService.HttpHeaderType.authorization.rawValue)
        networkLoader.loadData(using: request) { (data, _, error) in
            if let error = error {
                complete(error)
                return
            }
            guard let data = data,
                let childRep = NetworkService.decode(to: Child.self, data: data) as? ChildRepresentation
                else {
                    let error = NSError(domain: "ChildController.getChild.decodeData", code: NetworkService.NetworkError.badDecode.rawValue)
                    complete(error)
                    return
            }
            self.child = Child(representation: childRep)
            //TODO: Check for existing child in coredata, save if not
            complete(nil)
        }
    }
    
    func getChores(complete: @escaping NetworkService.CompletionWithError  = {error in}) {
        guard let bearer = bearer else {
            let error = NSError(domain: "ChildController.bearer", code: NetworkService.NetworkError.unauth.rawValue)
            complete(error)
            return
        }
        
        let childChoreURL = choreURL?.appendingPathComponent(bearer.id)
        guard var request = NetworkService.createRequest(url: childChoreURL, method: .get, headerType: .contentType, headerValue: .json) else {
            let error = NSError(domain: "ChildController.getChores.requestError", code: NetworkService.NetworkError.badRequest.rawValue)
            complete(error)
            return
        }
        
        
        
        request.setValue(bearer.token, forHTTPHeaderField: NetworkService.HttpHeaderType.authorization.rawValue)
        networkLoader.loadData(using: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            
            if let response = response, response.statusCode != 200 {
                let error = NSError(domain: "ChildController.getChores.responseError", code: response.statusCode)
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            
            guard let data = data else {
                let error = NSError(domain: "ChildController.getChild.decodeData", code: NetworkService.NetworkError.badDecode.rawValue)
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            
            guard let jsonChores = NetworkService.decode(to: AllChores.self, data: data) else {
                let error = NSError(domain: "ChildController.getChild.decodeData", code: NetworkService.NetworkError.badDecode.rawValue)
                DispatchQueue.main.async {
                    complete(error)
                }
                return
            }
            
            
            if let jsonChores = jsonChores as? AllChores {
                self.chores = jsonChores.chores
                DispatchQueue.main.async {
                    complete(nil)
                }
            }
        }
    }
    
    
    /**
     Get an array of chores from a Child Managed Object
     */
    func getChoresFromChild(child: Child) -> [Chore]? {
        guard let chores = child.chores else {return nil}
        return Array(chores) as? [Chore]
    }
    
    //MARK: Helper Methods
    /**
     Unwraps createRequest() and encodeUser()
     */
    private func createRequestAndEncodeUser(user: User, url: URL?, method: NetworkService.HttpMethod, headerType: NetworkService.HttpHeaderType, headerValue: NetworkService.HttpHeaderValue) -> URLRequest? {
        guard let request = NetworkService.createRequest(url: url, method: method, headerType: headerType, headerValue: headerValue) else {
            print(NSError(domain: "BadRequest", code: 400))
            return nil
        }
        let encodingStatus = NetworkService.encode(from: user, request: request)
        if let encodingError = encodingStatus.error {
            print(encodingError)
            return nil
        }
        guard let postRequest = encodingStatus.request else {
            print("post request error!")
            return nil
        }
        return postRequest
    }
    
    //MARK: Update
    /**
     Update chore on the API
     */
    func updateAPIChore(_ chore: Chore, complete: @escaping NetworkService.CompletionWithError  = {error in}) {
        guard let bearer = bearer else {
            let error = NSError(domain: "ChildController.bearer", code: NetworkService.NetworkError.unauth.rawValue)
            complete(error)
            return
        }
        
        let updateChoreURL = choreURL?.appendingPathComponent(String(chore.id))
        guard var request = NetworkService.createRequest(url: updateChoreURL, method: .put) else {
            let error = NSError(domain: "ChildController.updateChore: \(String(describing: chore.name)).requestError", code: NetworkService.NetworkError.badRequest.rawValue)
            complete(error)
            return
        }
        request.addValue(bearer.token, forHTTPHeaderField: NetworkService.HttpHeaderType.authorization.rawValue)
        
        URLSession.shared.dataTask(with: request) { (_, _, error) in
            if let error = error {
                complete(error)
                return
            }
            complete(nil)
        }.resume()
        
    }
    
    func updateMOCChore(_ chore: Chore, context: NSManagedObjectContext = CoreDataStack.shared.mainContext) {
        //save changes on disk
    }
    
    func updateChore(_ chore: Chore, context: NSManagedObjectContext = CoreDataStack.shared.mainContext) {
        updateAPIChore(chore)
        updateMOCChore(chore, context: context)
    }
    
    //MARK: MOCK DATA
    let mockChild = Child(id: 9001, name: "Johnny Appleseed", parentName: "Paul Bunyon")
    let mockChore = Chore(bonusPoints: 5, cleanStreak: 7, dueDate: Date(timeIntervalSinceNow: 900), id: 1, information: "Chop them well", parentId: 1, score: 9000, title: "Chop some trees")
}
