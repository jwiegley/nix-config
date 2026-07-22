We are debugging the C++ produced by the ingest pipeline from Torch Fx. You can read the Note in @src/Fx.hs for details on the Torch -> Bulk pipeline. After that it passes through Bulk, Loopy, Tron, and CPP intermediate representations.

The pipeline can be run via:
<command>
cabal run --flag +no-werror ingest  -- --model-name llama_3p1_8b_torch --output-dir ../h/tron/plugins/ --torch-trace-directory exports/meta-llama-Llama-3.1-8B-Instruct --dump-all && make -C ..
</command>

This will produce a number of IR dump files named model.* (e.g. @model.bulk, @model.loopy, @model.tron). It will also produce a C++ Tron plugin in @../h/tron/plugins.

The problem I am currently facing is: $ARGUMENTS

Note that the status quo reasons with the existing sglang frontend for the llama-3.1-8b model. This can be run using
<command>
cabal run --flag +no-werror ingest -- --model-name llama_3p1_8b --output-dir ../h/tron/plugins --bulk-trace-file model-trace.json --dump-all
</command>

It would be good to figure out why this works to determine whether changes to the backend are really needed or whether something needs to be changed in the frontend.

Once they have been built, both models can be tested with using
<command>
../gen/runtron --model llama_3p1_8b_torch stream-generate-text hello world
</command>
