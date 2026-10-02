# Run synthesis

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

source "$script_dir/create_project.tcl"

set reports_dir "$root_dir/reports"

if {![file exists $reports_dir]} {
    file mkdir $reports_dir
}

launch_runs synth_1 -jobs 12
wait_on_run synth_1

open_run synth_1

report_utilization -file "$reports_dir/synth_utilization.rpt"
report_timing_summary -file "$reports_dir/synth_timing_summary.rpt"

puts "Synthesis completed successfully."