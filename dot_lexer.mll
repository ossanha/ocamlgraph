(*
 * Graph: generic graph library
 * Copyright (C) 2004
 * Sylvain Conchon, Jean-Christophe Filliatre and Julien Signoles
 * 
 * This software is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License version 2, as published by the Free Software Foundation.
 * 
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * 
 * See the GNU Library General Public License version 2 for more details
 * (enclosed in the file LGPL).
 *)

(* $Id:$ *)

{
  open Lexing
  open Dot_ast
  open Dot_parser

  let string_buf = Buffer.create 1024
}

let alpha = ['a'-'z' 'A'-'Z' '_']
let digit = ['0'-'9']
let ident = alpha (alpha | digit)*
let number = '-'? ('.'['0'-'9']+ | ['0'-'9']+('.'['0'-'9']*)? )

let space = [' ' '\t' '\r' '\n']+

rule token = parse
  | space
      { token lexbuf }
  | ":" 
      { COLON }
  | "," 
      { COMMA }
  | ";" 
      { SEMICOLON }
  | "=" 
      { EQUAL }
  | "{" 
      { LBRA }
  | "}" 
      { RBRA }
  | "[" 
      { LSQ }
  | "]" 
      { RSQ }
  | "strict" 
      { STRICT }
  | "graph" 
      { GRAPH }
  | "digraph" 
      { DIGRAPH }
  | "subgraph" 
      { SUBGRAPH }
  | "node" 
      { NODE }
  | "edge" 
      { EDGE }
  | ident as s
      { ID (Ident s) }
  | number as s
      { ID (Number s) }
  | "\""
      { Buffer.clear string_buf; 
	ID (String (string lexbuf)) }
  | "<"
      { Buffer.clear string_buf; 
	html lexbuf; 
	ID (Html (Buffer.contents string_buf)) }
  | eof
      { EOF }
  | _ as c
      { failwith ("Dot_lexer: invalid character " ^ String.make 1 c) }

and string = parse
  | "\"" 
      { Buffer.contents string_buf }
  | "\\" "\""
      { Buffer.add_char string_buf '"';
	string lexbuf }
  | _ as c
      { Buffer.add_char string_buf c;
	string lexbuf }
  | eof
      { failwith ("Dot_lexer: unterminated string literal") }

and html = parse
  | ">"
      { () }
  | "<"
      { Buffer.add_char string_buf '<'; html lexbuf;
	Buffer.add_char string_buf '>'; html lexbuf }
  | _ as c
      { Buffer.add_char string_buf c;
	html lexbuf }
  | eof
      { failwith ("Dot_lexer: unterminated html literal") }