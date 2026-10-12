import Foundation

/// Presentation only: select and style three upstream graphs. Original graph
/// scripts, buckets, values, preferences and search callbacks stay unchanged.
enum AnkiStatisticsStyle {
    static func css(dark: Bool) -> String {
        """
        :root {
            --font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            --canvas: \(dark ? "#151515" : "#f9f9f7");
            --canvas-elevated: \(dark ? "#20201f" : "#ffffff");
            --fg: \(dark ? "#f9f9f7" : "#131313");
            --openanki-muted: \(dark ? "#a8a69e" : "#7b7974");
            --openanki-border: \(dark ? "#373735" : "#e9e8e3");
            --openanki-selection: \(dark ? "#3a2e27" : "#f5e9e3");
        }
        * { box-sizing: border-box; }
        body { margin: 0; font: 18px/1.5 var(--font-family); background: var(--canvas); -webkit-text-size-adjust: 100%; }
        .range-box {
            position: relative !important; top: auto !important;
            width: calc(100% - 32px) !important; max-width: 720px;
            margin: 16px auto 0; padding: 14px !important;
            border: 1px solid var(--openanki-border) !important;
            border-radius: 22px; background: var(--canvas-elevated) !important;
            display: grid; gap: 12px; font-size: 17px !important;
        }
        .range-box > div:not(.spin) { display: flex; flex-wrap: wrap; justify-content: flex-start; gap: 10px; font-size: 17px !important; }
        .range-box label { min-height: 42px; padding: 7px 12px !important; border-radius: 999px; gap: 5px; }
        .range-box label:has(input:checked) { background: var(--openanki-selection); }
        input { accent-color: \(dark ? "#e69b7e" : "#a64f33"); }
        #statisticsSearchText {
            flex-basis: 100%; width: 100%; min-height: 44px; font-size: 17px;
            padding: 9px 12px; border: 1px solid var(--openanki-border);
            border-radius: 12px; background: var(--canvas); color: var(--fg);
        }
        .range-box-pad { height: 18px !important; }
        .graphs-container {
            display: flex !important; flex-direction: column; gap: 18px !important;
            width: calc(100% - 32px) !important; max-width: 720px;
            margin: 0 auto !important; font-size: 18px !important;
        }
        .graphs-container > * { display: none !important; }
        .graphs-container > [data-openanki-graph] {
            display: flex !important; flex-direction: column;
            padding: 22px 18px 18px !important;
            border: 1px solid var(--openanki-border) !important;
            border-radius: 24px !important; box-shadow: none !important;
        }
        [data-openanki-graph="reviews"] { order: 0; }
        [data-openanki-graph="future"] { order: 1; }
        [data-openanki-graph="added"] { order: 2; }
        .graphs-container h1 { margin: 0 0 14px; padding: 0; border: 0 !important; font: 25px/1.3 Georgia, serif; color: var(--fg); }
        .graphs-container table, .graphs-container .subtitle, .graphs-container .help-badge,
        .graphs-container .graph > div[dir] { display: none !important; }
        .graphs-container .cumulative-overlay, .graphs-container .y2-ticks { display: none !important; }
        .graphs-container svg { display: block; width: 100%; overflow: visible; }
        .graphs-container .tick text { font-size: var(--openanki-tick-font, 26px) !important; opacity: 1 !important; fill: var(--openanki-muted); }
        .graphs-container .no-data text { font-size: var(--openanki-tick-font, 26px) !important; }
        .graphs-container svg:has(.no-data[opacity="1"]) .tick { visibility: hidden; }
        /* WebKit can consume the first tap when a mouse-hover tooltip appears. */
        .tooltip { display: none !important; }
        .hover-columns rect:hover { fill: none !important; opacity: 1 !important; }
        .spacer { height: 32px !important; }
        """
    }

    static func script(titles: [String: String]) throws -> String {
        let labels = String(decoding: try JSONEncoder().encode(titles), as: UTF8.self)
        return """
        (() => {
            const labels = \(labels);
            // Mouse-only tooltip updates can suppress WebKit's first touch
            // click. Keep the original click handler and its Anki query.
            document.addEventListener('mousemove', event => {
                if (event.target.closest?.('.hover-columns')) event.stopImmediatePropagation();
            }, true);
            let framePending = false;
            const resize = new ResizeObserver(() => schedule());
            const observed = new WeakSet();
            function restyle() {
                framePending = false;
                const root = document.querySelector('.graphs-container');
                if (!root) return;
                for (const container of root.children) {
                    const heading = container.querySelector('h1');
                    const title = heading?.textContent.trim();
                    const role = Object.keys(labels).find(key => labels[key] === title);
                    if (!role) continue;
                    if (container.dataset.openankiGraph !== role) container.dataset.openankiGraph = role;
                    for (const svg of container.querySelectorAll('svg')) {
                        if (!observed.has(svg)) { observed.add(svg); resize.observe(svg); }
                        const width = svg.getBoundingClientRect().width;
                        if (width > 0) {
                            const font = (15 * svg.viewBox.baseVal.width / width).toFixed(2) + 'px';
                            if (svg.style.getPropertyValue('--openanki-tick-font') !== font) svg.style.setProperty('--openanki-tick-font', font);
                        }
                        for (const bar of svg.querySelectorAll('g[class^="bars"] rect')) {
                            if (bar.getAttribute('rx') !== '6') { bar.setAttribute('rx', '6'); bar.setAttribute('ry', '6'); }
                        }
                        // Upstream click handlers belong to hover-column hit
                        // areas. Expose those existing targets to accessibility.
                        let index = 0;
                        for (const target of svg.querySelectorAll('.hover-columns rect.graph-element-clickable')) {
                            if (Number(target.getAttribute('height')) > 0) {
                                target.setAttribute('role', 'button');
                                target.setAttribute('aria-label', title + ' ' + (++index));
                            }
                        }
                    }
                }
            }
            function schedule() {
                if (framePending) return;
                framePending = true;
                requestAnimationFrame(restyle);
            }
            new MutationObserver(schedule).observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['height']});
            schedule();
        })();
        """
    }
}
