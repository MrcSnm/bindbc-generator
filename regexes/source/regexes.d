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
    replaceStruct = ctRegex!(r"\bstruct\b"),
    replaceArray = ctRegex!(r"((?:const\s)?\w+?\*?\s+?)(\w+?)\[([\w\d]+?)\]"),
    removeLoneVoid = ctRegex!(r"\(void\)"),
    replaceString = ctRegex!(r"const char\*")
}



enum GetFuncParamsAndName = ctRegex!(r"((?:const\s)?[\w*]+)\s+?(\w+)");
enum GetFuncParamsAndName2 = ctRegex!(r"((?:const\s)?.+?)\s([\w*]+)(\(.*\));", "m");
enum SingleSlash = ctRegex!(r"\\");

enum DollarToLib = ctRegex!(r"\$");