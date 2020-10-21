
//          Copyright Marcelo S. N. Mancini(Hipreme) 2020.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module regexes;
import std.regex : ctRegex;
enum Presets
{
    cimguiFuncs = ctRegex!(r"^(?:CIMGUI_API\s+)(.+\);)$", "mg"),
}

enum CPP_TO_D
{
    replaceUint = ctRegex!(r"unsigned\sint"),
    replaceUByte = ctRegex!(r"unsigned\schar"),
    replaceHeadConst = ctRegex!(r"const\s(.+?)\sconst"),
    replaceCallback = ctRegex!(r"([\w*]+?)\(\*(.+?)\)\((.+?)\)"),
    replaceIn = ctRegex!(r"\sin\b"),
    replaceOut = ctRegex!(r"\sout\b"),
    replaceAlign = ctRegex!(r"align\b"),
    replaceRef = ctRegex!(r"\sref\b"),
    //C++ part
    replaceTemplate = ctRegex!(r"(\w+?)<(\w+)>"),
    replaceAddress = ctRegex!(r"([\w<>\(\)!]+?)\s*&"),
    replaceNULL = ctRegex!(r"\sNULL\b"),
    replaceStruct = ctRegex!(r"\bstruct\b"),
    replaceArray = ctRegex!(r"((?:const\s)?\w+?\*?\s+?)(\w+?)\[([\w\d]*)\]"),
    replaceNullAddress = ctRegex!(r"\(\(void\*\)0\)"),
    removeLoneVoid = ctRegex!(r"\(void\)"),
    replaceString = ctRegex!(r"const char\*")
}



enum GetFuncParamsAndName = ctRegex!(r"((?:const\s)?[\w*]+)\s+?(\w+)");
enum GetFuncParamsAndName2 = ctRegex!(r"((?:const\s)?.+?)\s([\w*]+)(\(.*\));", "m");
enum SingleSlash = ctRegex!(r"\\");

enum DollarToLib = ctRegex!(r"\$");
