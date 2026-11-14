import { Controller } from "@hotwired/stimulus";

// Strict endless scroll for the feed and both views of the workout list. The
// wrapper's URL points at the next page; when the sentinel enters the viewport
// the page HTML is fetched, each item container is appended to the matching
// one by document order (the table view has two: the desktop rows and the
// phone list), and the next URL is read from the fetched wrapper.
// The sentinel carries a shape-matched skeleton while the fetch is in flight.
// A failed fetch backs off briefly and retries on the next intersection; at
// the end of the stream the controller stops. Without JavaScript the <noscript>
// pager remains the fallback.
//
// `dedupeAttribute` names a group-header attribute (the feed's `data-feed-day`
// separators): when a fetched page opens with a header carrying the same
// value as the last header already in the column, that duplicate is dropped
// so a day split across two pages keeps one separator. Empty by default, so
// the workout list is unaffected.
export default class extends Controller {
  static targets = ["items", "sentinel", "skeleton"];
  static values = {
    url: String,
    rootMargin: { type: String, default: "400px" },
    retryDelay: { type: Number, default: 3000 },
    dedupeAttribute: { type: String, default: "" },
  };

  connect() {
    this.abortController = new AbortController();
    this.retryAt = 0;
    this.observer = new IntersectionObserver(
      (entries) => entries.forEach((entry) => entry.isIntersecting && this.load()),
      { rootMargin: this.rootMarginValue }
    );
    if (this.urlValue) this.observer.observe(this.sentinelTarget);
  }

  disconnect() {
    this.observer?.disconnect();
    this.abortController?.abort();
  }

  async load() {
    if (this.loading || !this.urlValue || Date.now() < this.retryAt) return;

    this.loading = true;
    this.showSkeleton();
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" },
        signal: this.abortController.signal,
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const document = new DOMParser().parseFromString(await response.text(), "text/html");
      const fetched = document.querySelectorAll('[data-infinite-scroll-target="items"]');
      this.itemsTargets.forEach((target, index) => {
        const items = fetched[index];
        if (!items) return;

        const children = Array.from(items.children);
        this.dropDuplicateHeader(target, children);
        target.append(...children);
      });

      const next = document.querySelector("[data-infinite-scroll-url-value]");
      this.urlValue = next?.dataset.infiniteScrollUrlValue || "";
      if (!this.urlValue) this.stop();
    } catch (error) {
      if (error.name !== "AbortError") this.retryAt = Date.now() + this.retryDelayValue;
    } finally {
      this.loading = false;
      this.hideSkeleton();
    }
  }

  dropDuplicateHeader(target, children) {
    const attribute = this.dedupeAttributeValue;
    if (!attribute) return;

    const headers = target.querySelectorAll(`[${attribute}]`);
    const last = headers[headers.length - 1];
    const first = children[0];
    if (!last || !first?.hasAttribute(attribute)) return;
    if (first.getAttribute(attribute) === last.getAttribute(attribute)) children.shift();
  }

  showSkeleton() {
    if (this.hasSkeletonTarget) this.skeletonTarget.hidden = false;
  }

  hideSkeleton() {
    if (this.hasSkeletonTarget) this.skeletonTarget.hidden = true;
  }

  stop() {
    this.urlValue = "";
    this.observer?.disconnect();
    this.sentinelTarget.hidden = true;
  }
}
