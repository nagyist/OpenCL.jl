using FactCheck 

using OpenCL.CLAst 
using OpenCL.CLSourceGen

facts("Generation") do
    ast = CBinOp(CNum(1), 
                 CAdd(), 
                 CNum(1),
                 Int64)
    code = clsource(ast) 
    @fact code => "(1 + 1)"

    ast = CUnaryOp(CUAdd(), 
                   CName("foo"), 
                   Int64)
    code = clsource(ast) 
    @fact code => "(++(foo))"

    ast = CAssign(CName("foo"), 
                  CBinOp(CNum(1),
                         CAdd(),
                         CNum(1),
                         Int64),
                  Int64)
    code = clsource(ast)
    @fact code => "foo = (1 + 1)"

    ast = CBlock([CFunctionCall("foo", []), 
                  CFunctionCall("bar", [])])
    code = clsource(ast) 
    @fact code => "{{\n\tfoo();\n\tbar();\n}}\n"

    ast = CFor(CAssign(CName("i"), 
                       CNum(0),
                       Int64),
                     CBinOp(CName("i"), 
                            CLtE(), 
                            CNum(10),
                            Int64),
                     CUnaryOp(CUAdd(),
                              CName("i"),
                              Int64),
                     CBlock([CAssign(CName("i"),
                                     CNum(1),
                                     Int64)]))
    code = clsource(ast) 
    @fact code => "for (i = 0; (i <= 10); (++(i))) {{\n\ti = 1;\n}}\n"

    ast = CAssign(CSubscript(CName("test"),
                             CIndex(CNum(1))),
                  CNum(10),
                  Int64)
    code = clsource(ast) 
    @fact code => "test[1] = 10"
end