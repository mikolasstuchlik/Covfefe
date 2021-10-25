# Covfefe

[![Build Status](https://app.travis-ci.com/palle-k/Covfefe.svg?branch=master)](https://app.travis-ci.com/github/palle-k/Covfefe)
[![docs](https://cdn.rawgit.com/palle-k/Covfefe/66add420af3ce1801629d72ef0eedb9a30af584b/docs/badge.svg)](https://palle-k.github.io/Covfefe/)
[![CocoaPods](https://img.shields.io/cocoapods/v/Covfefe.svg)](https://cocoapods.org/pods/Covfefe)
![CocoaPods](https://img.shields.io/cocoapods/p/Covfefe.svg)
[![license](https://img.shields.io/github/license/palle-k/Covfefe.svg)](https://github.com/palle-k/Covfefe/blob/master/License)

Covfefe is a parser framework for languages generated by any (deterministic or nondeterministic) context free grammar.
It implements the [Earley](https://en.wikipedia.org/wiki/Earley_parser) and [CYK](https://en.wikipedia.org/wiki/CYK_algorithm) algorithm.

## Usage

### Swift Package Dependency in Xcode

1. Go to "File" > "Swift Packages" > "Add Package Dependency..."
2. Enter "https://github.com/palle-k/Covfefe.git" as the repository URL.
3. Select "Version", "Up to next major", "0.6.1" < "1.0.0"
4. Add Covfefe to your desired target.

### Swift Package Manager

This framework can be imported as a Swift Package by adding it as a dependency to the `Package.swift` file:

```swift
.package(url: "https://github.com/palle-k/Covfefe.git", from: "0.6.1")
```

### CocoaPods

Alternatively, it can be added as a dependency via CocoaPods (iOS, tvOS, watchOS and macOS).

```ruby
target 'Your-App-Name' do
  use_frameworks!
  pod 'Covfefe', '~> 0.6.1'
end
```

## Examples

There are multiple ways for expressing a grammar. Both examples declare the same grammar. 
This grammar describes simple mathematical expressions consisting of unary and binary operations and parentheses.
A syntax tree can be generated, which describes how a given word was derived from the grammar above:

### Textual declarations
Grammars can be specified in a superset of EBNF or a superset of BNF, which adopts some features of EBNF (documented [here](/BNF.md)).
Alternatively, ABNF is supported.

```swift
let grammarString = """
expression       = binary-operation | brackets | unary-operation | number | variable;
brackets         = '(', expression, ')';
binary-operation = expression, binary-operator, expression;
binary-operator  = '+' | '-' | '*' | '/';
unary-operation  = unary-operator, expression;
unary-operator   = '+' | '-';
number           = {digit};
digit            = '0' ... '9';
variable         = {letter};
letter           = 'A' ... 'Z' | 'a' ... 'z';
""" 
let grammar = try Grammar(ebnf: grammarString, start: "expression")

let parser = EarleyParser(grammar: grammar)
 
let syntaxTree = try parser.syntaxTree(for: "(a+b)*(-c)")
 ```

![Example Syntax Tree](https://raw.githubusercontent.com/palle-k/Covfefe/master/example-syntax-tree.png)

### Declaration via Result Builder
Grammar can be initialized using Result Builder called `GrammarBuilder`. The Result Builder collects  the inidividual productions and combines them. 

Production rule is declared using operator ` <non-terminal-name> --> <productions>` which expects `String` representing the name of the non-terminal on the left side and possible productions on the right side.

**Concatenation**
Use operator `<+>` in order to declare a concatenation of terminals and non-terminals. 

**Alternations**
Use operator `<|>` in order to declare an alternation. Alternation operator has lower precedence than concatenation operator. 

**Non-terminal**
If the non-terminal is on the left side of `-->` operator, the non-terminal is represented by a `String` literal. If the non-terminal is on the right side if `-->` operator, use free function `n(_:)` which accepts the name of the non-terminal as the argument.

**Terminal**
Terminal may be declared in multiple ways. We recognize 4 types of terminals: strings, character ranges, regular expressions and character sets.
 * Use `t(_:)` to initialize a terminal representing either `String` or `CharacterSet`. For example `t("Hello")` or `t(.letters)`.
 * Use `re(_:)` to initialize a terminal representing a regular expression. For example `re("[^*(]")`
 * Use `ra(_:)` to initialize a terminal representing a range of characters. For example `ra("A" ... "Z")`
 * Use `t()` to initialize an empty word - the `ϵ` word.

```swift
let directGrammar = Grammar(start: "expression") {
    "expression"        --> n("binary-operation")
                        <|> n("brackets")
                        <|> n("unary-operation")
                        <|> n("number")
                        <|> n("variable")

    "brackets"          --> t("(") <+> n("expression") <+> t(")")

    "binary-operation"  --> n("expression") <+> n("binary-operator") <+> n("expression")

    "binary-operator"   --> t("+")
                        <|> t("-")
                        <|> t("*")
                        <|> t("/")

    "unary-operation"   --> n("unary-operator") <+> n("expression")

    "unary-operator"    --> t("+")
                        <|> t("-")

    "number"            --> n("digit")
                        <|> n("digit") <+> n("number")

    "digit"             --> t(.decimalDigits)

    "variable"          --> n("letter")
                        <|> n("letter") <+> n("variable")

    "letter"            --> t(.letters)
}

let parser = EarleyParser(grammar: directGrammar)

let syntaxTree = try parser.syntaxTree(for: "(a+b)*(-c)")
```
