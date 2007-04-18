open Format
open Graph.Pack.Graph
open Outils_tort
open Outils_math


let debug_graphEdGTK = ref false

let _ = GMain.Main.init ()
 
let graph = parse_gml_file Sys.argv.(1)

exception Choose of V.t

type t = V.t
type label = V.t
let label x = x
let string_of_label x = string_of_int (V.label x)
let label_of_string x = try int_of_string x with Failure _ -> 0

(* [step_from n] computes the best `distance' for solving the
   dictator's problem in the complex hyperbolic plane for [n]
   dictators.  In a half-plane, we have to use the distance
   given by [step_from (2*n)] or, better, the distance given
   by [step_from (2*max(3 n))]. *)
let step_from n =
  ath (tan (pi_over_4 -. pi/.float(2*n)))


(* [hspace_dist_sqr turtle] computes the square of the distance
   between the origin and the half-space in front of [turtle]. *)
let hspace_dist_sqr turtle =
  let (ax, ay) = turtle.pos
  and (dx, dy) = turtle.dir in
 (* if ax*.dx +. ay*.dy < 0.0 then 0.0 else*)
  begin
    let ux = dy and uy = -.dx in
    let alpha = ax*.ax +. ay*.ay
    and beta = 2.0*.(ax*.ux +. ay*.uy) in
    if beta = 0.0 then
      alpha
    else
      begin
	let gamma = (1.0 +. alpha)/.beta in
	let delta = gamma*.gamma -. 1.0 in
	let sol =
          if beta > 0.0
          then -.gamma +. sqrt(delta)
          else -.gamma -. sqrt(delta) in
	let (zx, zy) = translate (ax, ay) (ux*.sol, uy*.sol) in
	zx*.zx +. zy*.zy
      end
  end ;;



let edge v w = mem_edge graph v w || mem_edge graph w v 

let make_subgraph l =
  let gl = create () in
  List.iter (fun v -> add_vertex gl v) l;
  List.iter 
    (fun v -> List.iter (fun w -> if edge v w then add_edge gl v w) l) 
   l; 
  (* TODO: efficacite *)
  gl

let order_children l =
  let gl = make_subgraph l in
  let scc = Components.scc_list gl in
  let order_component c =
    let gc = make_subgraph c in
    let v = match c with
      | v :: l ->
	  List.fold_left 
	    (fun m v -> if out_degree gc v < out_degree gc m then v else m)
	    v l
      | [] -> 
	  assert false
    in 
    let l = ref [] in
    Dfs.prefix_component (fun w -> l := w :: !l) gc v;
    !l
  in
  let scc = List.map order_component scc in
  List.flatten scc


let rlimit = 0.90 
let rlimit_sqr = rlimit *. rlimit

module Model = struct

  open Gobject.Data
  let cols = new GTree.column_list
  let name = cols#add string
  let vertex = cols#add caml
    
  let model = GTree.tree_store cols

  let rows = Hashtbl.create 97

  let add_vertex v =
    let row = model#append () in
    model#set ~row ~column:name (string_of_int (V.label v));
    model#set ~row ~column:vertex v;
    Hashtbl.add rows v row;
    row

  let add_edge_1 row_v w =
    let row = model#append ~parent:row_v () in
    model#set ~row ~column:name (string_of_int (V.label w))

  let () =
    iter_vertex
      (fun v -> 
	 let row = add_vertex v in
	 iter_succ (add_edge_1 row) graph v)
      graph

  let add_edge v w =
    let row_v = Hashtbl.find rows v in
    add_edge_1 row_v w;
    if not is_directed then 
      let row_w = Hashtbl.find rows w in
      add_edge_1 row_w v

end

let model = Model.model

open GtkTree



(* Ouverture fenetre GTK *)
let window = GWindow.window ~border_width: 10 ~title:"GraphEd" ~position: `CENTER () 
let h_box = GPack.hbox ~homogeneous:false ~spacing:30  ~packing:window#add ()
let sw = GBin.scrolled_window ~shadow_type:`ETCHED_IN ~hpolicy:`NEVER
  ~vpolicy:`AUTOMATIC ~packing:h_box#add () 
let canvas = GnoCanvas.canvas ~aa:true ~width:(truncate w) ~height:(truncate h) ~packing:h_box#add () 
let canvas_root = canvas#root 



let root = 
  try
    iter_vertex (fun v -> raise (Choose v)) graph;
    Format.eprintf "empty graph@."; exit 0
  with Choose v ->
    ref v



module Vset = Set.Make(V)
let vset_of_list = List.fold_left (fun s x -> Vset.add x s) Vset.empty


module H = Hashtbl.Make(V)

(* table donnant pour chaque noeud sa profondeur et sa tortue *)
let pos = H.create 97

(* table des ellipses existantes *)
let ellipses = H.create 97

let tdraw_string_gtk v tor canvas =
  let ellipse =
    try
      let item = H.find ellipses v in
      item#parent#show();
      item
    with Not_found ->
      let (w,h) = (40,15) in
      let noeud = GnoCanvas.group ~x:0.0 ~y:0.0 canvas in
      let ellipse = GnoCanvas.ellipse 
	~props:[ `X1  ( float_of_int (-w/2)); `Y1 (float_of_int (-h/2)); 
		 `X2  (float_of_int (w/2)) ; `Y2 ( float_of_int (h/2)) ;
		 `FILL_COLOR "grey" ; `OUTLINE_COLOR "black" ; `WIDTH_PIXELS 0 ] noeud  in
      let s = string_of_label v in
      let _ = GnoCanvas.text ~props:[`X 0.0; `Y 0.0 ; `TEXT s;  `FILL_COLOR "blue"] noeud in
      H.add ellipses v ellipse;
      ellipse
  in
  tdraw_string_gtk tor ellipse;
  ellipse

module H2 = Hashtbl.Make(struct type t = V.t * V.t
		 	        let hash (v,w) = Hashtbl.hash (V.hash v, V.hash w)
			        let equal (v1,w1) (v2,w2) = V.equal v1 v2 && V.equal w1 w2 end)


let grey_edges = H2.create 97

let draw_grey_edge vw tv tw canvas =
  let (x,y) = let (x ,y ) = from_tortue tv.pos in ((float_of_int x),(float_of_int y)) in
  let (x',y') = let (x',y') = from_tortue tw.pos in ((float_of_int x'),(float_of_int y')) in
  let rapport = 1.95 in
  let p = GnomeCanvas.PathDef.new_path () in
  GnomeCanvas.PathDef.moveto p x y ;
  GnomeCanvas.PathDef.curveto p ((x+. x')/.rapport) ((y +. y')/.rapport) 
				 ((x  +.x')/.rapport) ((y +. y')/.rapport)
				 x' y' ;
  (*            debug            *)
  if  !debug_graphEdGTK 
  then 
    ( 
      let (v,w)=  
	let (v,w) = vw in 
	(string_of_label v, string_of_label w) in
      eprintf "tortue %s \t tortue %s@." v w
    );
  (*            /debug            *)
  try
    let l = H2.find grey_edges vw in
    l#show();
    l#set [`BPATH p];
    l
  with Not_found ->

    let l = GnoCanvas.bpath canvas
      ~props:[ `BPATH p ; `OUTLINE_COLOR "SlateGrey" ; `WIDTH_PIXELS 1 ] in
    l#lower_to_bottom ();
    H2.add grey_edges vw l;
    l
 
let black_edges = H2.create 97

let tdraw_edge_gtk vw t distance etapes canvas =
 let line =
    try
      H2.find black_edges vw
    with Not_found ->
      let color = "black" in 
      let l = GnoCanvas.line canvas ~props:[ `FILL_COLOR color ;`WIDTH_PIXELS 1; `SMOOTH true] in
      H2.add black_edges vw l;
      l
 in
 tdraw_edge_gtk t distance etapes line

let color_change_intern_edge color node = 
iter_edges
    (fun _ w ->
       try
	 let n = H2.find grey_edges (node,w) in
	 n#set [`OUTLINE_COLOR color]
       with Not_found ->
	 try
	 let n = H2.find grey_edges (w,node) in
	 n#set [`OUTLINE_COLOR color]
	 with Not_found ->
	   ()
    )
  graph


let color_change_direct_edge color node = 
iter_edges
    (fun _ w ->
       try
	 let n = H2.find black_edges (node,w) in
	 n#set [`FILL_COLOR color]
       with Not_found ->
	 try
	   let n = H2.find black_edges (w,node) in
	   n#set [`FILL_COLOR color]
	 with Not_found ->
	   ()
    )
    graph
  


  

let step = ref 0
  
let rec draw_graph depth noeud tortue canvas =
  if !debug_graphEdGTK 
  then 
    (let (x,y) = tortue.pos in
     Format.eprintf "  hspace : %f\t pos : %f %f \tnoeud : %s@."
       ( hspace_dist_sqr tortue )x y(string_of_label noeud);
    ); 
  if hspace_dist_sqr tortue <= rlimit_sqr then
    begin
      H.add pos noeud (depth,tortue);
      tmoveto_gtk tortue;
      (* draw label *)
      let ellipse = tdraw_string_gtk noeud tortue canvas in
      let sigs = ellipse#parent#connect in
      let _ = sigs#event (drag_label noeud ellipse) in
      
      let l = succ graph noeud in 
      let l = List.filter (fun x -> not (H.mem pos x) ) l in
      List.iter (fun w -> H.add pos w (depth+1, tortue)) l;
      let l = order_children l in
      let n = List.length l in
      if n > 0 then
	begin
	  let distance = step_from (max 3 n)
	  and angle = (if depth = 0 then 2. else 1.) *. pi /. (float_of_int n) in
	  let tortue = if depth = 0 then tortue else turn_right tortue ((pi -. angle) /. 2.) in
	  let _ = draw_edges noeud (depth+1) tortue distance angle canvas l in
	  ()
	end;
      ellipse#parent#raise_to_top();
    end
  else
    try
      let ellipse = tdraw_string_gtk noeud tortue canvas in
      ellipse#parent#hide();
     (* H.remove pos noeud*)
    with Not_found -> Format.eprintf"je devrai pas etre la@."

and draw_edges noeud depth t distance angle canvas= function
  | [] -> 
      []
  | v :: l -> 
      let etapes = 1 in
      let tv = tdraw_edge_gtk (noeud,v) t distance etapes canvas in 
      (*if hspace_dist_sqr t <= rlimit_sqr then H.add pos v (depth,tv);*)
      let t = turn_left t angle in
      let l = (v,tv) :: draw_edges noeud depth t distance angle canvas l in
      draw_graph depth v tv canvas;
      l


and drag_label noeud item ev =
  begin match ev with
    | `ENTER_NOTIFY _ ->
	item#set [ `FILL_COLOR "steelblue" ];
	color_change_intern_edge "LightSteelBlue" noeud ; 
	color_change_direct_edge "LightSteelBlue" noeud 
    | `LEAVE_NOTIFY ev ->
	let state = GdkEvent.Crossing.state ev in
	if not (Gdk.Convert.test_modifier `BUTTON1 state)
	then item#set [ `FILL_COLOR "grey" ; ];
	color_change_intern_edge "SlateGrey" noeud ;
	color_change_direct_edge "black" noeud 
    | `BUTTON_RELEASE ev ->
	item#parent#ungrab (GdkEvent.Button.time ev)
    | `MOTION_NOTIFY ev ->
	incr step;
	let state = GdkEvent.Motion.state ev in
	if Gdk.Convert.test_modifier `BUTTON1 state && !step mod 3 = 0 then 
	  begin
	    let curs = Gdk.Cursor.create `FLEUR in
	    item#parent#grab [`POINTER_MOTION; `BUTTON_RELEASE] curs (GdkEvent.Button.time ev);
	    let ibounds = item#parent#get_bounds in
 	    let z1 =  to_tortue(truncate((ibounds.(0)+.ibounds.(2))/.2.),
				truncate((ibounds.(1)+. ibounds.(3))/.2.)) in
	    let mx = GdkEvent.Motion.x ev in
	    let my = GdkEvent.Motion.y ev in
	    let z2 = to_tortue (truncate mx, truncate my) in
	    let (x,y) = drag_origin !origine z1 z2 in
	    origine := (x,y);
	    let  tor = make_turtle !origine 0.0 in
	    draw tor canvas_root;
	  end
    | `BUTTON_PRESS ev ->
	if (GdkEvent.Button.button ev) = 3
        then
	  begin
            let loc_menu = GMenu.menu () in
            let factory =
              new GMenu.factory loc_menu in
            ignore (factory#add_item "  Ajouter un successeur" ~callback: (ajout_successeur noeud));
            loc_menu#popup
              ~button:3
              ~time:(GdkEvent.Button.time ev);
          end
    | _ ->
	()
  end;
  true

and ajout_successeur noeud () =
  let window = GWindow.window ~title: "Choix du nom du label" ~width: 300 ~height: 50 () in
  let vbox = GPack.vbox ~packing: window#add () in
  
  let entry = GEdit.entry ~max_length: 50 ~packing: vbox#add () in
  entry#set_text "Label";
  entry#select_region ~start:0 ~stop:entry#text_length;
  window#show ();
  let _ = entry#connect#activate 
    ~callback: (fun () ->
		  let text = entry#text in
		  let label = label_of_string text in
		  let vertex = V.create label in
		  add_vertex graph vertex;
		  add_edge graph noeud vertex;
		  window#destroy ();
		  ignore (Model.add_vertex vertex);
		  Model.add_edge noeud vertex;
		  let  tor = make_turtle !origine 0.0 in
		  draw tor canvas_root)
  in
  ()

and draw tortue canvas =
  H.clear pos;

  draw_graph 0 !root tortue canvas;
  (* draw intern edges *)
  iter_edges
    (fun v w ->
       try
	 let lv,tv = H.find pos v in
	 let lw,tw = H.find pos w in 
	 if abs (lw - lv) <> 1 && (lv <> 0 || lw <> 0)
	 then
	   (*            debug            *)
	   (if !debug_graphEdGTK 
	    then
		(Format.eprintf "tortue : %s\t\t\t tortue : %s@." (string_of_label v) (string_of_label w);
		 let (x ,y ) = from_tortue tv.pos 
		 and (x',y') = from_tortue tw.pos in
		 Format.eprintf "pos  x:%d y:%d \t pos x:%d y:%d@." x y x' y';
		);	    
	    ignore(draw_grey_edge (v,w) tv tw canvas)
	   );
	 (*            /debug             *)
       with Not_found ->
	 begin 
	   (*            debug            *)
	   if !debug_graphEdGTK then Format.eprintf"Je vais tenter de détruire un edge@.";
	   (*            /debug           *)
	   try
	     let l = H2.find grey_edges (w,v) in  l#hide();
	     (*            debug            *)
	     if !debug_graphEdGTK then Format.eprintf"J'ai détruit un grey edge@.";
	     (*            /debug           *)
	   with Not_found -> ();
	   try
	     let l = H2.find grey_edges (v,w) in  l#hide();
	     (*            debug            *)
	     if !debug_graphEdGTK then Format.eprintf"J'ai détruit un grey edge@.";
	     (*            /debug           *)
	   with Not_found -> ();
	(*     try 
	       let l = H2.find black_edges (v,w) in List.iter (fun v -> v#hide()) l ;
	       Format.eprintf"J'ai détruit un black edge@."
	     with Not_found -> ()*)
	 end
    ) 
    graph


let node_selection ~(model : GTree.tree_store) path =
  let row = model#get_iter path in
  let v = model#get ~row ~column: Model.vertex in
  root := v;
  let tortue =
    let (x,y) = from_tortue !origine in
    moveto_gtk x y;
    make_turtle !origine 0.0;
  in
  let l =  canvas_root#get_items in
  (*Format.eprintf "il y a %d elements dans le canvas @." (List.length l);*)
  List.iter (fun v -> v#hide())l;
H2.clear grey_edges;
H2.clear black_edges;
  draw tortue canvas_root

    
let add_columns ~(view : GTree.view) ~model =
  let renderer = GTree.cell_renderer_text [`XALIGN 0.] in
  let vc =
    GTree.view_column ~title:"Nodes" ~renderer:(renderer, ["text", Model.name]) ()
  in
  ignore (view#append_column vc);
  vc#set_sizing `FIXED;
  vc#set_fixed_width 100;
  view#selection#connect#after#changed ~callback:
    begin fun () ->
      List.iter
        (fun p -> node_selection ~model p)
	view#selection#get_selected_rows;
    end
    


let _ = window#connect#destroy~callback:GMain.Main.quit 


let treeview = GTree.view ~model ~packing:sw#add ()
let () = treeview#set_rules_hint true
let () = treeview#selection#set_mode `MULTIPLE
let _ = add_columns ~view:treeview ~model
(*let _ = treeview#misc#connect#realize ~callback:treeview#expand_all*)
 
(* la zone d'affichage du graph, le canvas *)
let tortue =
  let (x,y) = from_tortue !origine in
  moveto_gtk x y;
  make_turtle !origine 0.0 

let () = canvas#set_scroll_region 0. 0. w h 

  
(* l'affichage de la fenetre principale *)
let () = window#show ()

let _ = draw tortue canvas_root

let () = GMain.Main.main ()