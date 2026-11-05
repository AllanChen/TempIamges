'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
type Command = {
  id: string;
  name: string;
  description: string;
  inputTypes: string[];
};
type Widget = {
  id: string;
  version: string;
  name: string;
  summary: string;
  author: string;
  iconURL: string;
  official: boolean;
  commands: Command[];
  privacy: { notice: string };
};
const API_URL = 'https://glance-service.allanchanni.workers.dev/api/v2/widgets';
function send(type: string, widgetID: string) {
  const h = window.webkit?.messageHandlers?.glanceWidgetMarket;
  if (!h) return false;
  h.postMessage({ type, widgetID });
  return true;
}
export default function WidgetMarket() {
  const [widgets, setWidgets] = useState<Widget[]>([]),
    [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading'),
    [installed, setInstalled] = useState<string[]>([]),
    [notice, setNotice] = useState(''),
    [selected, setSelected] = useState<Widget | null>(null),
    [reload, setReload] = useState(0);
  useEffect(() => {
    window.glanceSetInstalled = (ids) => {
      setInstalled(ids);
      localStorage.setItem('glance-installed-widgets', JSON.stringify(ids));
    };
    try {
      const saved = JSON.parse(
        localStorage.getItem('glance-installed-widgets') ?? '[]',
      );
      if (Array.isArray(saved))
        setInstalled(
          saved.filter((id): id is string => typeof id === 'string'),
        );
    } catch {}
    setStatus('loading');
    fetch(API_URL, { headers: { Accept: 'application/json' } })
      .then((r) => {
        if (!r.ok) throw Error();
        return r.json();
      })
      .then((b) => {
        setWidgets(
          (b as { result?: { widgets?: Widget[] } }).result?.widgets ?? [],
        );
        setStatus('ready');
      })
      .catch(() => setStatus('error'));
  }, [reload]);
  function manage(w: Widget) {
    const a = installed.includes(w.id);
    if (!send(a ? 'uninstallWidget' : 'installWidget', w.id)) {
      setNotice('Open this page inside Glance to manage Widgets.');
      return;
    }
    setInstalled((v) => {
      const next = a ? v.filter((id) => id !== w.id) : [...v, w.id];
      localStorage.setItem('glance-installed-widgets', JSON.stringify(next));
      return next;
    });
    setNotice(
      `${w.name} ${a ? 'was uninstalled' : 'is now available'} in Glance.`,
    );
  }
  return (
    <main className="min-h-screen bg-[#0b0b0d] text-[#f3eee8]">
      <header className="mx-auto flex max-w-6xl items-end justify-between gap-6 px-6 pb-10 pt-10 sm:px-10 sm:pt-16">
        <div>
          <p className="mb-4 text-xs font-semibold uppercase tracking-[0.28em] text-[#e8a87c]">
            Glance 2.0
          </p>
          <h1 className="text-5xl font-semibold tracking-[-0.055em] sm:text-7xl">
            Widget Market
          </h1>
          <p className="mt-5 max-w-xl text-base leading-7 text-white/55">
            Small, focused tools that appear where you already preview your
            media.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => setReload((value) => value + 1)}
            className="rounded-full border border-[#e8a87c]/50 px-4 py-2 text-sm text-[#f5d2b8] transition hover:bg-[#e8a87c]/15"
          >
            Refresh
          </button>
          <Link
            href="/"
            className="hidden rounded-full border border-white/15 px-4 py-2 text-sm text-white/65 sm:block"
          >
            ← Glance home
          </Link>
        </div>
      </header>
      <section className="mx-auto max-w-6xl px-6 pb-24 sm:px-10">
        {notice && (
          <output className="mb-6 block rounded-2xl border border-[#e8a87c]/30 bg-[#e8a87c]/10 px-5 py-4 text-sm text-[#f5d2b8]">
            {notice}
          </output>
        )}
        {status === 'loading' && (
          <div className="rounded-3xl border border-white/10 p-10 text-white/55">
            Loading the official catalog…
          </div>
        )}
        {status === 'error' && (
          <div
            role="alert"
            className="rounded-3xl border border-red-300/20 p-10 text-red-100"
          >
            The Widget Market is temporarily unavailable.
          </div>
        )}
        {status === 'ready' && (
          <div className="grid gap-5 md:grid-cols-2">
            {widgets.map((w) => (
              <article
                key={w.id}
                onClick={() => setSelected(w)}
                className="group cursor-pointer rounded-3xl border border-white/10 bg-[#141417] p-5 transition hover:-translate-y-0.5 hover:border-[#e8a87c]/40"
              >
                <div className="flex gap-4">
                  <img
                    src={w.iconURL}
                    alt=""
                    className="h-16 w-16 rounded-2xl object-cover"
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <h2 className="text-xl font-semibold">{w.name}</h2>
                        <p className="mt-1 text-xs text-white/40">
                          Official by {w.author} · v{w.version}
                        </p>
                      </div>
                      <span className="rounded-full bg-[#e8a87c]/10 px-2.5 py-1 text-[10px] uppercase text-[#f5d2b8]">
                        Cloud
                      </span>
                    </div>
                    <p className="mt-4 text-sm leading-6 text-white/60">
                      {w.summary}
                    </p>
                  </div>
                </div>
                <div className="mt-5 border-t border-white/10 pt-4">
                  <p className="text-xs text-white/40">
                    {w.commands.length === 1
                      ? w.commands[0].name
                      : `${w.commands.length} Commands · ${w.commands.map((c) => c.name).join(', ')}`}
                  </p>
                  <div className="mt-4 flex items-center justify-between gap-4">
                    <p className="text-xs text-white/35">{w.privacy.notice}</p>
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        manage(w);
                      }}
                      className="shrink-0 rounded-full bg-[#e8a87c] px-4 py-2 text-sm font-semibold text-[#171214]"
                    >
                      {installed.includes(w.id) ? 'Uninstall' : 'Install'}
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
        {selected && (
          <div
            className="fixed inset-0 z-10 flex items-center justify-center bg-black/70 p-6"
            onClick={() => setSelected(null)}
          >
            <div
              className="w-full max-w-lg rounded-3xl border border-white/10 bg-[#18181c] p-7 shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center gap-4">
                <img
                  src={selected.iconURL}
                  alt=""
                  className="h-16 w-16 rounded-2xl"
                />
                <div>
                  <h2 className="text-2xl font-semibold">{selected.name}</h2>
                  <p className="text-sm text-white/45">
                    by {selected.author} · v{selected.version}
                  </p>
                </div>
              </div>
              <p className="mt-6 leading-7 text-white/70">{selected.summary}</p>
              <h3 className="mt-6 text-sm font-semibold uppercase tracking-widest text-[#e8a87c]">
                Commands
              </h3>
              <div className="mt-3 space-y-2">
                {selected.commands.map((c) => (
                  <div key={c.id} className="rounded-xl bg-white/[.05] p-3">
                    <p className="font-medium">{c.name}</p>
                    <p className="mt-1 text-sm text-white/50">
                      {c.description}
                    </p>
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={() => setSelected(null)}
                className="mt-7 rounded-full border border-white/15 px-4 py-2 text-sm"
              >
                Close
              </button>
            </div>
          </div>
        )}
      </section>
    </main>
  );
}
declare global {
  interface Window {
    glanceSetInstalled?: (ids: string[]) => void;
    webkit?: {
      messageHandlers?: {
        glanceWidgetMarket?: { postMessage: (message: unknown) => void };
      };
    };
  }
}
