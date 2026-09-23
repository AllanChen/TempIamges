import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen bg-[#0b0b0d] text-[#f3eee8]">
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-6 py-7 sm:px-10">
        <Link href="/" className="flex items-center gap-3" aria-label="Glance home"><span className="grid h-9 w-9 place-items-center rounded-xl bg-[#e8a87c] text-sm font-black text-[#171214]">G</span><span className="font-semibold tracking-[0.18em] text-sm uppercase">Glance</span></Link>
        <Link href="/widgets" className="rounded-full border border-white/15 px-4 py-2 text-sm text-[#f5d2b8] transition hover:border-[#e8a87c]/70 hover:bg-white/5">Widget Market <span aria-hidden="true">↗</span></Link>
      </nav>
      <section className="mx-auto grid max-w-6xl gap-12 px-6 pb-24 pt-16 sm:px-10 lg:grid-cols-[1.1fr_.9fr] lg:items-center lg:pt-28">
        <div><p className="mb-5 text-xs font-semibold uppercase tracking-[0.28em] text-[#e8a87c]">Quick preview, deeper work</p><h1 className="max-w-3xl text-5xl font-semibold leading-[0.98] tracking-[-0.055em] sm:text-7xl">The fastest way to see what you meant.</h1><p className="mt-7 max-w-xl text-lg leading-8 text-white/60">Glance turns selected links, files, images, and videos into a calm native preview. Add cloud tools from the Widget Market when the next step needs more power.</p><Link href="/widgets" className="mt-9 inline-flex items-center gap-3 rounded-full bg-[#e8a87c] px-6 py-3 font-semibold text-[#171214] transition hover:bg-[#f2bd99]">Explore Widget Market <span aria-hidden="true">→</span></Link></div>
        <div className="relative overflow-hidden rounded-[2rem] border border-white/10 bg-[#151519] p-5 shadow-2xl shadow-black/30"><div className="absolute -right-24 -top-24 h-64 w-64 rounded-full bg-[#e8a87c]/10 blur-3xl" /><div className="relative rounded-[1.35rem] border border-white/10 bg-[#0e0e11] p-5"><div className="mb-10 flex items-center justify-between text-xs text-white/45"><span>IMAGE INSPECT</span><span>⌘ ⇧ G</span></div><div className="grid aspect-square place-items-center rounded-2xl bg-gradient-to-br from-[#2a2423] via-[#161518] to-[#25202a]"><span className="text-7xl font-light text-[#e8a87c]/70">✦</span></div><div className="mt-5 flex items-center justify-between"><span className="text-sm text-white/65">Drop a file. Keep moving.</span><span className="rounded-full bg-white/10 px-3 py-1 text-xs text-[#f5d2b8]">Glance</span></div></div></div>
      </section>
    </main>
  );
}
