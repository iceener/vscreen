# Notes

## Seam

- `.pi/extensions/limen.ts` and `.omp/extensions/limen.ts` are identical. `findPackage()` now returns `undefined` instead of throwing; the default export returns early when no root is found. Keep the two files identical.

## Check

Run from the repo root. `/tmp/nodeonly` holds only a `node` symlink, so PATH has node but no limen.

```sh
mkdir -p /tmp/nodeonly && ln -sf "$(command -v node)" /tmp/nodeonly/node
CHECK='const c=[];const pi=new Proxy({},{get:(_,k)=>(...a)=>{c.push(k)}});for(const f of [".pi",".omp"]){c.length=0;await (await import(`./${f}/extensions/limen.ts`)).default(pi);console.log(f,"loaded;",c.length,"hook registrations")}'
env -u LIMEN_PACKAGE PATH=/tmp/nodeonly:/usr/bin:/bin node --no-warnings --input-type=module -e "$CHECK"   # 0 registrations, exit 0
env -u LIMEN_PACKAGE node --no-warnings --input-type=module -e "$CHECK"                                   # 17 registrations with limen on PATH
```

Real startup, no tokens spent (a bogus key makes the model call fail with 401 after extensions load):

```sh
env -u LIMEN_PACKAGE PATH=/tmp/nodeonly:/usr/bin:/bin "$(command -v pi)" -a --offline --no-session --provider anthropic --model claude-haiku-4-5 --api-key invalid-key -p hi
```

Before the fix this printed `Failed to load extension ... limen is not on PATH` and exited before the model call. After the fix it reaches the 401.

Run real-startup checks with `LIMEN_JOB*` unset when limen is on PATH. The hooks act on the job named in the environment.
