# soc_top place-and-route attempt a4 (issue #37)

- **Layout state**: floorplan, placement and CTS completed; **global route failed** (`GRT-0116`). No routed DEF, GDS or SPEF exists. No timing or Fmax figure is claimed.
- **Arrangement**: Baseline arrangement with every macro moved up 5.44 um (two site rows); nothing else changed.
- **Channel demand** (`scripts/pnr_channel_capacity.py`): 144 / 70 / 144 pins in 78.5 um gaps, whole arrangement shifted.
- **Result**: global-route total congestion **5119** (router table `Total` row; die 1950 x 1950 um unchanged, placement density 0.45, 50 congestion iterations, `route_allow_congestion` false).
- **Where the overflow is** (`scripts/pnr_congestion_by_region.py`, `congestion_by_region.txt`): the macro-interior tiles with capacity 0 carry nearly all of it.
- Files: `pnr_request.json` (the request run), `soc_top_route_metrics.json`, `global_route_diagnostic.log` (a second `global_route` on the same CTS database with `-congestion_report_file`, the source of the by-region file; its per-region overflow sum equals the total the klt run reported).
