(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2007 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)


(* Generic xml parsing module
 * Uses xmlm library *)

type error = XmlError of string | Empty | UnknownType | Internal
type format = Podcast | Xspf | Smil | Asx
exception Error of error

let string_of_error e =
  match e with
    | XmlError s -> Printf.sprintf "xml error: %s" s
    | Empty -> "no interesting data in Xml"
    | UnknownType -> "unknown Xml type"
    | Internal -> "xmliq internal error"

let raise e = raise (Error e)

(** Wrapper to parse data from Xmlm and return
  * a xml tree as previously returned by xml-light *)
type xml =
  |  Element of (string * (string * string) list * xml list)
  |  PCData of string

let parse_string s =
  let source = `String (0,s) in
  let input = Xmlm.make_input source in
  (* Map a tag representation in xmlm to
   * (name, attributes list) where attribute = string*string. *)
  let make_tag (x,l) = 
    (* Forget about the uri attribute *)
    let l = 
      List.map (fun ((_,y),z) -> (y,z)) l 
    in
    snd x,l
  in
  let rec get_elems l =
    if Xmlm.eoi input then
      l
    else
      match Xmlm.input input with
        | `El_start tag -> 
            let elem = get_elems [] in
            let (name,attributes) = make_tag tag in
            get_elems ((Element (name,attributes,List.rev elem)) :: l)
        | `El_end -> l
        | `Data s -> 
            get_elems ((PCData s) :: l)
        | `Dtd _ -> get_elems l
  in
  try
    let elems = get_elems [] in
    Element ("",[],List.rev elems)
  with
    | Xmlm.Error (_,e) -> raise (XmlError (Xmlm.error_message e))

let rec lowercase_tags xml =
  match xml with
    | Element(s,l,x) ->
        Element(String.lowercase s,
                    List.map
                      (fun (a,b) -> (String.lowercase a,b))
                      l,
                    List.map lowercase_tags x)
    | _ -> xml


let rec get_format x =
   (* Assume any rss is a podcast due to broken
    * implementation.. *)
   (* let rec match_rss l =
     match l with
       | (s,s') :: l' when s = "xmlns:itunes" -> Podcast
       | _ :: l' -> match_rss l'
       | [] -> raise UnknownType
   in *)
  match x with
    | Element(s,l,x) :: l' when s = "playlist" -> Xspf
    | Element(s,l,x) :: l' when s = "rss" -> Podcast (* match_rss l *)
    | Element(s,l,x) :: l' when s = "smil" -> Smil
    | Element(s,l,x) :: l' when s = "asx" -> Asx
    | Element(s,l,x) :: l' -> get_format (l' @ x)
    | _ :: l' -> get_format l'
    | [] -> raise UnknownType

let podcast_uri l x =
  try
    List.assoc "url" l
  with
    | _ -> raise Empty

let xspf_uri l x =
  match x with
    | PCData(v) :: [] -> v
    | _ -> raise Empty

let asx_uri l x =
  try
    List.assoc "href" l
  with
    | _ -> raise Empty

(* Should return useful markup values for parsing:
 * author,location,track,extract loc function *)
let xml_spec f =
  match f with
    | Podcast -> "itunes:author","enclosure","item",podcast_uri 
    | Xspf -> "creator","location","track",xspf_uri
    | Asx -> "author","ref","entry",asx_uri
    | _ -> raise Internal

let xml_tracks t xml =
  let author,location,track,extract = xml_spec t in
  let rec get_tracks l r =
    match l with
      | Element (s,_,x) :: l' when s = track -> get_tracks l' (x :: r)
      | Element (s,_,x) :: l' -> get_tracks (l' @ x) r
      | _ :: l' -> get_tracks l' r
      | [] -> r
  in
  let tracks = get_tracks [xml] [] in
  let rec parse_uri l =
    match l with
      | Element (s,l,x) :: l' when s = location -> extract l x
      | Element (_,_,_) :: l' -> parse_uri l'
      | _ :: l' -> parse_uri l'
      | [] -> raise Empty
  in
  let rec parse_metadatas m l =
    match l with
      | Element (s,_,PCData(x) :: []) :: l' when s = author 
           -> ("artist",x) :: (parse_metadatas m l')
      | Element (s,_,PCData(x) :: []) :: l' -> (s,x) :: (parse_metadatas m l')
      | _ :: l' -> (parse_metadatas m l')
      | [] -> m
  in
  let rec parse_tracks t r =
    match t with
      | track :: l -> 
         begin
          try 
            parse_tracks l 
                ((parse_metadatas [] track, parse_uri track) :: 
                  r)
          with 
            | Error Empty -> parse_tracks l r
         end
      | [] -> r
  in
  parse_tracks tracks []

let smil_tracks xml =
  let rec get_tracks r l =
    match l with
      | Element ("audio",l',x) :: l'' -> get_tracks (l' :: r) l''
      | Element (s,_,x) :: l' -> get_tracks r (l' @ x)
      | _ :: l' -> get_tracks r l'
      | [] -> r
  in
  let tracks = get_tracks [] [xml] in
  let smil_uri l =
    try
      List.assoc "src" l
    with _ -> raise Internal
  in
  let rec smil_meta m l =
    match l with
      | (s,s') :: l' when s = "author" -> ("artist",s') :: (smil_meta m l')
      | (s,s') :: l' -> (s, s') :: (smil_meta m l')
      | [] -> m
  in
  let rec parse_tracks t r =
    match t with
      | track :: l -> 
         parse_tracks l 
             (try (smil_meta [] track, smil_uri track) :: r with Error Empty -> r)
      | [] -> r
  in
    parse_tracks tracks []


let tracks xml =
  let xml = lowercase_tags (parse_string xml) in
  let t =  get_format [xml] in
  match t with
    | Podcast | Xspf | Asx -> xml_tracks t xml
    | Smil -> smil_tracks xml
