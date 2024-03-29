
//          Copyright Marcelo S. N. Mancini(Hipreme) 2020.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module regexes;
public import std.regex;
enum Presets
{
    cimguiFuncs = ctRegex!(r"^(?:CIMGUI_API\s+)(.+\);)$", "mg"),
}

enum CPP_TO_D
{
    replaceUint = ctRegex!(r"unsigned int"),
    replaceUByte = ctRegex!(r"unsigned char"),
    replaceHeadConst = ctRegex!(r"const (.+?) const"),
    replaceCallback = ctRegex!(r"([\w*]+?)\(\*(.+?)\)\((.+?)\)"),
    replaceIn = ctRegex!(r"\sin\b"),
    replaceOut = ctRegex!(r"\sout\b"),
    replaceAlign = ctRegex!(r"align\b"),
    replaceRef = ctRegex!(r"\sref\b"),
    replaceSizeof = ctRegex!(r"sizeof\(([\w*]+)\)"),
    //C++ part
    replaceTemplate = ctRegex!(r"(\w+?)<([\w,\s\(\)]+)>"),
    //Can match for instance:
    //string& something = "test"
    //MyClass<T> t = MyClass<T>(args)
    replaceAddressDefault = ctRegex!(`([\w<>!]+?)\s*&\s*(\w+)\s*=\s*(?:(?:\"|\')\w+(?:\"|\')|([\w<>]+\s*\(?[\w,'"]*\)?))`),
    replaceAddress = ctRegex!(r"([\w<>\(\)!]+?)\s*&"),
    replaceNULL = ctRegex!(r"\sNULL\b"),
    replaceCONST = ctRegex!(r"CONST\s+(\w+\s*\*)"),

    replaceStruct = ctRegex!(r"\bstruct\b"),
    replaceArray = ctRegex!(r"((?:const\s)?\w+?\*?\s+?)(\w+?)\[([\w\d]*)\]"),
    replaceNullAddress = ctRegex!(r"\(\(void\*\)0\)"),
    removeLoneVoid = ctRegex!(r"\(void\)"),
    replaceString = ctRegex!(r"const char\*"),
    
    hasDefaultArg = ctRegex!(r"\s*=\s*")
}



enum GetFuncParamsAndName = ctRegex!(r"((?:const\s)?[\w*]+)\s+?(\w+)");
enum GetFuncParamsAndName2 = ctRegex!(r"((?:const\s)?.+?)\s([\w*]+)(\(.*\));", "m");
enum SingleSlash = ctRegex!(r"\\");

enum DollarToLib = ctRegex!(r"\$");
