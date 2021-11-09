//
//  SyntaxTree.swift
//  Covfefe
//
//  Created by Palle Klewitz on 07.08.17.
//  Copyright (c) 2017 Palle Klewitz
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

/// A tree which can store different types of values in its leafs
///
/// - leaf: A leaf
/// - node: A node with a key and an arbitrary list of elements
public enum SyntaxTree<Element, LeafElement> {
	/// A leaf storing a leaf element
	case leaf(LeafElement)
	
	/// A node with a key and an arbitrary list of elements
	case node(key: Element, children: [SyntaxTree])
}

public extension SyntaxTree {
	typealias IndexPath = [Int]

	subscript(_ indexPath: IndexPath) -> SyntaxTree? {
		var current = self
		for index in indexPath {
			if case let .node(_, children) = current {
				current = children[index]
			}
			return nil
		}

		return current
	}
}

public extension SyntaxTree {
    private enum IterateStackFrame {
        case children(key: Element, children: [SyntaxTree], index: Int)
    }

	func iterate(
		nextSubtree: (_ indexPath: IndexPath, _ currentItem: SyntaxTree, _ shouldEnterSubtree: inout Bool) throws ->  Void,
		nodeIterarionComplete: ((_ indexPath: IndexPath, _ key: Element, _ continueIterating: inout Bool) throws -> Void)? = nil
	) rethrows {
        var stack = [IterateStackFrame]()
		var indexPath = IndexPath()

        func appendNew(_ tree: SyntaxTree) throws {
            var shouldEnterSubtree = true
            try nextSubtree(indexPath, tree, &shouldEnterSubtree)
            if 
                shouldEnterSubtree,
                case let .node(key: key, children: children) = tree 
            {
                stack.append(.children(key:key, children: children, index: 0))
				indexPath.append(0)
            }
        }

        func resolve(key: Element, children: [SyntaxTree], iteratedIndex: Int) throws {
			indexPath.removeLast()

			guard children.count > iteratedIndex else {
				var continueIterating = true
				try nodeIterarionComplete?(indexPath, key, &continueIterating)
				if !continueIterating {
					stack.removeAll()
				}
				return
            } 

			indexPath.append(iteratedIndex)
            stack.append(.children(key: key, children: children, index: iteratedIndex + 1))
			try appendNew(children[iteratedIndex])
        }

        try appendNew(self)
        while let currentFrame = stack.popLast() {
            switch currentFrame {
            case let .children(key: key, children: children, index: index):
                try resolve(key: key, children: children, iteratedIndex: index)
            }
        }
    }

}


public extension SyntaxTree {
    private enum ExplostionStackFrame {
        case result([SyntaxTree])
        case current(key: Element, children: [SyntaxTree], shouldExplodeResult: Bool, accumulator: [SyntaxTree], iteratedIndex: Int)
    }

	/// Explodes nodes and passes all child nodes to the parent node if the given closure returns true
	///
	/// - Parameter shouldExplode: Determines if a node should be exploded
	/// - Returns: A tree generated by exploding nodes determined by the given predicate
	func explode(_ shouldExplode: (Element) throws -> Bool) rethrows -> [SyntaxTree<Element, LeafElement>] {
        var stack = [ExplostionStackFrame]()
        var lastResult: [SyntaxTree]?

        func appendNew(_ tree: SyntaxTree) throws {
            switch tree {
            case .leaf:
                stack.append(.result([tree]))
            case .node(key: let key, children: let children):
                stack.append(.current(key: key, children: children, shouldExplodeResult: try shouldExplode(key), accumulator: [], iteratedIndex: 0))
            }
        }

        func resolve(key: Element, children: [SyntaxTree], shouldExplodeResult: Bool, accumulator: [SyntaxTree], iteratedIndex: Int, lastResult: [SyntaxTree]?) throws {
            var newAccumulator = accumulator
            if let result = lastResult {
                newAccumulator.append(contentsOf: result)
            }

            guard children.count > iteratedIndex else {
                if shouldExplodeResult {
                    stack.append(.result(newAccumulator))
                } else {
                    stack.append(.result([.node(key: key, children: newAccumulator)]))
                }
                return
            }

            let child = children[iteratedIndex]

            stack.append(.current(key: key, children: children, shouldExplodeResult: shouldExplodeResult, accumulator: newAccumulator, iteratedIndex: iteratedIndex + 1))
            try appendNew(child)

        }

        try appendNew(self)

        while let currentFrame = stack.popLast() {
            switch currentFrame {
            case let .result(result):
                lastResult = result
            case let .current(key: key, children: children, shouldExplodeResult: shouldExplodeResult, accumulator: accumulator, iteratedIndex: iteratedIndex):
                try resolve(key: key, children: children, shouldExplodeResult: shouldExplodeResult, accumulator: accumulator, iteratedIndex: iteratedIndex, lastResult: lastResult)
                lastResult = nil
            }
        }

        return lastResult!
	}
}

public extension SyntaxTree {

    func reduce<T>(_ initial: T, next: (_ currentItem: SyntaxTree, _ result: inout T, _ shouldContinue: inout Bool) throws ->  Void ) rethrows -> T {
        var accumulator = initial

		try iterate { _, item, shouldContinue in
			try next(item, &accumulator, &shouldContinue)
		}

        return accumulator
    }

	/// Generates a new syntax tree by applying the transform function to every key of the tree
	///
	/// - Parameter transform: Transform function
	/// - Returns: A tree generated by applying the transform function to every key
	func map<Result>(_ transform: (Element) throws -> Result) rethrows -> SyntaxTree<Result, LeafElement> {
		var mapped = [Result]()
		var trees = [[SyntaxTree<Result, LeafElement>]()]

		try iterate { _, item, _ in
			switch item {
			case let .leaf(leaf):
				trees[trees.count - 1].append(.leaf(leaf))
			case let .node(key: key, children: _):
				mapped.append(try transform(key))
				trees.append([])
			}
		}
		nodeIterarionComplete: { _, _, _ in 
			let newMapped = mapped.popLast()!
			let newChildren = trees.popLast()!
			trees[trees.count - 1].append(.node(key: newMapped, children: newChildren))
		}

		return trees.first!.first!
	}

	/// Generates a new syntax tree by applying the transform function to every leaf of the tree
	///
	/// - Parameter transform: Transform function
	/// - Returns: A tree generated by applying the transform function to every leaf value
	func mapLeafs<Result>(_ transform: (LeafElement) throws -> Result) rethrows -> SyntaxTree<Element, Result> {
		var trees = [[SyntaxTree<Element, Result>]()]

		try iterate { _, item, _ in
			switch item {
			case let .leaf(leaf):
				trees[trees.count - 1].append(.leaf(try transform(leaf)))
			case .node:
				trees.append([])
			}
		}
		nodeIterarionComplete: { _, key, _ in 
			let newChildren = trees.popLast()!
			trees[trees.count - 1].append(.node(key: key, children: newChildren))
		}

		return trees.first!.first!
	}
	
	/// All leafs of the tree
	var leafs: [LeafElement] {
		self.reduce([]) { current, accumulator, _ in
            if case let .leaf(leaf) = current {
                accumulator.append(leaf)
            }
        }
	}
	
	/// Filters the tree by removing all nodes and their corresponding subtrees if the given predicate is false
	///
	/// - Parameter predicate: Predicate to filter the tree
	/// - Returns: A tree generated by filtering out nodes for which the predicate returned false
	func filter(_ predicate: (Element) throws -> Bool) rethrows -> SyntaxTree<Element, LeafElement>? {
		var trees = [[SyntaxTree]()]

		try iterate { _, item, enterNode in
			switch item {
			case let .leaf(leaf):
				trees[trees.count - 1].append(.leaf(leaf))
			case let .node(key: key, children: _) where try predicate(key):
				trees.append([])
			case .node:
				enterNode = false
			}
		}
		nodeIterarionComplete: { _, key, _ in 
			let newChildren = trees.popLast()!
			trees[trees.count - 1].append(.node(key: key, children: newChildren))
		}

		return trees.first!.first
	}

	/// Filters the tree by removing all leafs if the given predicate is false
	///
	/// - Parameter predicate: Predicate to filter the tree
	/// - Returns: A tree generated by filtering out leafs for which the predicate returned false
	func filterLeafs(_ predicate: (LeafElement) throws -> Bool) rethrows -> SyntaxTree<Element, LeafElement>? {
		var trees = [[SyntaxTree]()]

		try iterate { _, item, _ in
			switch item {
			case let .leaf(leaf) where try predicate(leaf):
				trees[trees.count - 1].append(.leaf(leaf))
			case .node:
				trees.append([])
			default:
				break
			}
		}
		nodeIterarionComplete: { _, key, _ in 
			let newChildren = trees.popLast()!
			trees[trees.count - 1].append(.node(key: key, children: newChildren))
		}

		return trees.first!.first
	}
	
	
	/// Compresses the tree by exploding nodes which have exactly one child node
	///
	/// - Returns: Tree generated by compressing the current tree
	func compressed() -> SyntaxTree<Element, LeafElement> {
		var trees = [[SyntaxTree]()]

		iterate { _, item, _ in
			switch item {
			case let .leaf(leaf):
				trees[trees.count - 1].append(.leaf(leaf))
			case .node:
				trees.append([])
			}
		}
		nodeIterarionComplete: { _, key, _ in 
			let newChildren = trees.popLast()!
			if newChildren.count == 1 {
				trees[trees.count - 1].append(contentsOf: newChildren)
			} else {
				trees[trees.count - 1].append(.node(key: key, children: newChildren))
			}
		}

		return trees.first!.first!
	}
	
	/// Returns all nodes which match the given predicate.
	///
	///
	/// - Parameter predicate: Predicate to match
	/// - Returns: A collection of nodes which match the given predicate
	func allNodes(where predicate: (Element) throws -> Bool) rethrows -> [SyntaxTree<Element, LeafElement>] {
		try reduce([]) { item, result, _ in
			if case let .node(key, _) = item, try predicate(key) {
				result.append(item)
			}
		}
	}
}

extension SyntaxTree: CustomDebugStringConvertible {
	/// - Warning: This function is implemented using recursion.
	public var debugDescription: String {
		switch self {
		case .leaf(let value):
			return "leaf (value: \(value))"
			
		case .node(key: let key, children: let children):
			let childrenDescription = children.map{$0.debugDescription}.joined(separator: "\n").replacingOccurrences(of: "\n", with: "\n\t")
			return """
			node (key: \(key)) {
				\(childrenDescription)
			}
			"""
		}
	}
}

extension SyntaxTree: CustomStringConvertible {
	/// - Warning: This function is implemented using recursion.
	public var description: String {
		var id = 0
		let uniqueKeyTree = self.map { element -> (Int, Element) in
			let uniqueElement = (id, element)
			id += 1
			return uniqueElement
		}.mapLeafs { leaf -> (Int, LeafElement) in
			let uniqueLeaf = (id, leaf)
			id += 1
			return uniqueLeaf
		}
		
		
		func generateDescription(_ tree: SyntaxTree<(Int, Element), (Int, LeafElement)>) -> String {
			switch tree {
			case .leaf(let leaf):
				let (id, leafElement) = leaf
                let leafDescription = "\(leafElement)"
                    .literalEscaped
                    .replacingOccurrences(of: "\"", with: "\\\"")
				return "node\(id) [label=\"\(leafDescription)\" shape=box]"
				
			case .node(key: let key, children: let children):
				let (id, element) = key
				let childrenDescriptions = children.map(generateDescription).filter{!$0.isEmpty}.joined(separator: "\n")
				let childrenPointers = children.compactMap{ node -> Int? in
					if let id = node.root?.0 {
						return id
					} else if let id = node.leaf?.0 {
						return id
					} else {
						return nil
					}
				}.map{"node\(id) -> node\($0)"}.joined(separator: "\n")
				
				var result = "node\(id) [label=\"\(element)\"]"
				if !childrenPointers.isEmpty {
					result += "\n\(childrenPointers)"
				}
				if !childrenDescriptions.isEmpty {
					result += "\n\(childrenDescriptions)"
				}
				
				return result
			}
		}
		
		func allLeafIDs(_ tree: SyntaxTree<(Int, Element), (Int, LeafElement)>) -> [Int] {
			switch tree {
			case .leaf(let leaf):
				return [leaf.0]
				
			case .node(key: _, children: let children):
				return children.flatMap(allLeafIDs)
			}
		}
		
		return """
		digraph {
			\(generateDescription(uniqueKeyTree).replacingOccurrences(of: "\n", with: "\n\t"))
			{
				rank = same
				\(allLeafIDs(uniqueKeyTree).map(String.init).map{"node\($0)"}.joined(separator: "\n\t\t"))
			}
		}
		"""
	}
}

/// Determines if two syntax trees are equal to each other.
///
/// This function returns true, if both trees have the same structure, equal keys in equal nodes and equal leafs
///
/// - Parameters:
///   - lhs: First tree to compare
///   - rhs: Second tree to compare
/// - Returns: A boolean value indicating whether the provided trees are equal to each other
///
/// - Warning: This function is implemented using recursion.
public func == <Element: Equatable, LeafElement: Equatable>(lhs: SyntaxTree<Element, LeafElement>, rhs: SyntaxTree<Element, LeafElement>) -> Bool {
	switch (lhs, rhs) {
	case let (.leaf(lhs), .leaf(rhs)) where lhs == rhs :
		return true
		
	case (.node(key: let lKey, children: let lChildren), .node(key: let rKey, children: let rChildren)):
		let result = lKey == rKey && lChildren.count == rChildren.count && !zip(lChildren, rChildren).allSatisfy(==)
		return result
	default:
		return false
	}
}

public extension SyntaxTree {
	
	/// Creates a new syntax tree node with a given key and a list of children
	///
	/// - Parameters:
	///   - key: Root key
	///   - children: Children of the root node
	init(key: Element, children: [SyntaxTree<Element, LeafElement>]) {
		self = .node(key: key, children: children)
	}
	
	/// Creates a new syntax tree with a given root key and no children
	///
	/// - Parameter key: Root key
	init(key: Element) {
		self = .node(key: key, children: [])
	}
	
	/// Creates a new syntax tree with a given leaf value
	///
	/// - Parameter value: Leaf value
	init(value: LeafElement) {
		self = .leaf(value)
	}
}

public extension SyntaxTree where LeafElement == () {
	/// Creates an empty tree
	init() {
		self = .leaf(())
	}
}

public extension SyntaxTree {
	
	/// Returns the root key of the tree or nil if no root key exists
	var root: Element? {
		guard case .node(key: let root, children: _) = self else {
			return nil
		}
		return root
	}
	
	/// Returns the value stored in the current node if the current node is a leaf. Otherwise, nil is returned
	var leaf: LeafElement? {
		guard case .leaf(let leaf) = self else {
			return nil
		}
		return leaf
	}
	
	/// Returns the direct children of the root node
	var children: [SyntaxTree<Element, LeafElement>]? {
		switch self {
		case .leaf:
			return nil
			
		case .node(key: _, children: let children):
			return children
		}
	}
}
