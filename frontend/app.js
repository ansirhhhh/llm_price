/**
 * AI模型价格比价平台 - Frontend Logic
 */

// --- Constants ---
const API_URL = "/api/prices";
const AUTO_REFRESH_MS = 30 * 60 * 1000; // 30 minutes

// --- State ---
let allModels = [];
let filteredModels = [];
let currentSort = { field: null, direction: "asc" };
let isLoading = false;

// --- DOM refs ---
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

const tableBody = $("#price-table-body");
const tableWrapper = $(".table-wrapper");
const searchInput = $("#search-input");
const searchClear = $("#search-clear");
const providerFilter = $("#provider-filter");
const freeOnlyCheckbox = $("#free-only");
const refreshBtn = $("#refresh-btn");
const modelCount = $("#model-count");
const updateTime = $("#update-time");
const staleBadge = $("#stale-badge");
const emptyState = $("#empty-state");
const loadingState = $("#loading-state");
const errorState = $("#error-state");
const errorMsg = $("#error-msg");

// --- Fetch ---
async function fetchPrices() {
    if (isLoading) return;
    isLoading = true;
    showLoading();

    try {
        const resp = await fetch(API_URL);
        if (!resp.ok) {
            throw new Error(`服务器返回错误: ${resp.status} ${resp.statusText}`);
        }
        const result = await resp.json();
        allModels = result.data || [];
        updateMeta(result);
        populateProviderFilter();
        applyFiltersAndSort();
        showTable();
    } catch (err) {
        console.error("Failed to fetch prices:", err);
        errorMsg.textContent = err.message || "无法加载价格数据";
        showError();
    } finally {
        isLoading = false;
    }
}

// --- Meta info ---
function updateMeta(result) {
    modelCount.textContent = result.count ?? allModels.length;
    if (result.as_of) {
        const d = new Date(result.as_of);
        updateTime.textContent = d.toLocaleString("zh-CN", {
            year: "numeric", month: "2-digit", day: "2-digit",
            hour: "2-digit", minute: "2-digit",
        });
    } else {
        updateTime.textContent = "未知";
    }
    if (result.stale) {
        staleBadge.style.display = "inline-block";
    } else {
        staleBadge.style.display = "none";
    }
}

// --- Provider filter ---
function populateProviderFilter() {
    const providers = [...new Set(allModels.map((m) => m.provider).filter(Boolean))].sort((a, b) =>
        a.localeCompare(b, "zh")
    );
    const currentValue = providerFilter.value;
    providerFilter.innerHTML = '<option value="">全部提供商</option>';
    providers.forEach((p) => {
        const opt = document.createElement("option");
        opt.value = p;
        opt.textContent = p;
        providerFilter.appendChild(opt);
    });
    providerFilter.value = currentValue;
}

// --- Filter & Sort ---
function applyFiltersAndSort() {
    const query = searchInput.value.trim().toLowerCase();
    const provider = providerFilter.value;
    const freeOnly = freeOnlyCheckbox.checked;

    filteredModels = allModels.filter((m) => {
        // Text search
        if (query) {
            const modelId = (m.model_id || "").toLowerCase();
            const providerName = (m.provider || "").toLowerCase();
            if (!modelId.includes(query) && !providerName.includes(query)) {
                return false;
            }
        }
        // Provider filter
        if (provider && m.provider !== provider) {
            return false;
        }
        // Free only
        if (freeOnly) {
            const inputFree = m.input_price === 0 || m.input_price === null;
            const outputFree = m.output_price === 0 || m.output_price === null;
            if (!inputFree || !outputFree) {
                return false;
            }
        }
        return true;
    });

    // Sort
    if (currentSort.field) {
        const field = currentSort.field;
        const dir = currentSort.direction === "asc" ? 1 : -1;
        filteredModels.sort((a, b) => {
            let va = a[field];
            let vb = b[field];

            // Treat null/undefined as -Infinity for prices (so they sort last in desc)
            if (va == null && vb == null) return 0;
            if (va == null) return 1;
            if (vb == null) return -1;

            if (typeof va === "string") va = va.toLowerCase();
            if (typeof vb === "string") vb = vb.toLowerCase();

            if (va < vb) return -1 * dir;
            if (va > vb) return 1 * dir;
            return 0;
        });
    }

    renderTable();
}

// --- Render ---
function renderTable() {
    tableBody.innerHTML = "";

    if (filteredModels.length === 0) {
        tableWrapper.style.display = "none";
        emptyState.style.display = "block";
        modelCount.textContent = "0";
        return;
    }

    tableWrapper.style.display = "block";
    emptyState.style.display = "none";
    modelCount.textContent = filteredModels.length;

    filteredModels.forEach((m) => {
        const row = document.createElement("tr");

        const inputPrice = formatPrice(m.input_price);
        const outputPrice = formatPrice(m.output_price);
        const contextWin = formatContext(m.context_window);
        const isFree = m.input_price === 0 && m.output_price === 0;
        const hasUrl = m.url && m.url.trim() !== "";

        const displayTitle = m.display_name && m.display_name !== m.model_id
            ? `title="${escapeHtml(m.display_name)}"` : "";

        row.innerHTML = `
            <td>
                <span class="model-name" ${displayTitle}>${escapeHtml(m.model_id)}</span>
                ${isFree ? '<span class="free-badge">免费</span>' : ""}
            </td>
            <td><span class="provider-badge">${escapeHtml(m.provider)}</span></td>
            <td class="col-price">
                <span class="${inputPrice.cssClass}">${inputPrice.text}</span>
            </td>
            <td class="col-price">
                <span class="${outputPrice.cssClass}">${outputPrice.text}</span>
            </td>
            <td class="col-context">
                <span class="context-value">${contextWin}</span>
            </td>
            <td class="col-action">
                ${hasUrl
                    ? `<a href="${escapeHtml(m.url)}" target="_blank" rel="noopener noreferrer"
                        class="btn-link" title="前往官方定价页面">🔗 前往</a>`
                    : '<span class="btn-link btn-link-disabled">无链接</span>'}
            </td>
        `;
        tableBody.appendChild(row);
    });
}

// --- Formatters ---
function formatPrice(price) {
    if (price == null) {
        return { text: "-", cssClass: "price-na" };
    }
    if (price === 0) {
        return { text: "免费", cssClass: "price-free" };
    }
    return {
        text: `$${price.toFixed(2)}`,
        cssClass: "price-paid",
    };
}

function formatContext(context) {
    if (context == null) return "-";
    if (context >= 1_000_000) {
        return `${(context / 1_000_000).toFixed(0)}M`;
    }
    if (context >= 1_000) {
        return `${(context / 1_000).toFixed(0)}K`;
    }
    return context.toLocaleString();
}

function escapeHtml(str) {
    if (!str) return "";
    const div = document.createElement("div");
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
}

// --- State toggles ---
function showLoading() {
    loadingState.style.display = "block";
    tableWrapper.style.display = "none";
    emptyState.style.display = "none";
    errorState.style.display = "none";
}

function showTable() {
    loadingState.style.display = "none";
    errorState.style.display = "none";
}

function showError() {
    loadingState.style.display = "none";
    tableWrapper.style.display = "none";
    emptyState.style.display = "none";
    errorState.style.display = "block";
}

// --- Event handlers ---
searchInput.addEventListener("input", () => {
    searchClear.classList.toggle("visible", searchInput.value.length > 0);
    applyFiltersAndSort();
});

searchClear.addEventListener("click", () => {
    searchInput.value = "";
    searchClear.classList.remove("visible");
    searchInput.focus();
    applyFiltersAndSort();
});

providerFilter.addEventListener("change", applyFiltersAndSort);
freeOnlyCheckbox.addEventListener("change", applyFiltersAndSort);

refreshBtn.addEventListener("click", () => {
    refreshBtn.textContent = "⏳ 刷新中...";
    refreshBtn.disabled = true;
    fetchPrices().finally(() => {
        refreshBtn.textContent = "🔄 刷新";
        refreshBtn.disabled = false;
    });
});

// --- Column sorting ---
$$("#price-table th.sortable").forEach((th) => {
    th.addEventListener("click", () => {
        const field = th.dataset.sort;
        if (!field) return;

        // Toggle direction
        if (currentSort.field === field) {
            currentSort.direction = currentSort.direction === "asc" ? "desc" : "asc";
        } else {
            currentSort.field = field;
            currentSort.direction = "asc";
        }

        // Update header styles
        $$("#price-table th.sortable").forEach((h) => {
            h.classList.remove("sorted", "sorted-asc", "sorted-desc");
        });
        th.classList.add("sorted");
        th.classList.add(currentSort.direction === "asc" ? "sorted-asc" : "sorted-desc");

        applyFiltersAndSort();
    });
});

// --- Auto-refresh ---
let autoRefreshTimer = setInterval(fetchPrices, AUTO_REFRESH_MS);

// --- Keyboard shortcut: Ctrl+F focuses search ---
document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "f") {
        // Don't prevent default entirely — only if search is not already focused
        if (document.activeElement !== searchInput) {
            e.preventDefault();
            searchInput.focus();
            searchInput.select();
        }
    }
    // F5 or Ctrl+R triggers refresh
    if (e.key === "F5" || ((e.ctrlKey || e.metaKey) && e.key === "r")) {
        // Let the browser handle it — we refresh on DOMContentLoaded
    }
});

// --- Init ---
document.addEventListener("DOMContentLoaded", () => {
    fetchPrices();
});
