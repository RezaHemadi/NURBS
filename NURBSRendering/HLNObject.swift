//
//  HLNObject.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import Foundation

// Base class for every NURBS object
class HLNObject: ObservableObject, Identifiable {
    // MARK: - Properties
    var id: UUID
    var name: String?
    var type: HLNObjectType
    @Published var hidden: Bool = false
    @Published var selected: Bool = false
    
    // MARK: - Initialization
    init(name: String? = nil, type: HLNObjectType) {
        self.name = name
        self.type = type
        id = UUID()
    }
}
extension HLNObject: Equatable {
    static func == (lhs: HLNObject, rhs: HLNObject) -> Bool {
        lhs.id == rhs.id
    }
    
    
}

extension HLNObject: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum HLNObjectType {
    case curve
    case surface
}
