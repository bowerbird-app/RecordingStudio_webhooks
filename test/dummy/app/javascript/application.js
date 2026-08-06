// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { application } from "controllers/application"

if (!window.recordingStudioWebhooksCopyUrlBound) {
	window.recordingStudioWebhooksCopyUrlBound = true

	const fallbackCopy = (text) => {
		const textarea = document.createElement("textarea")
		textarea.value = text
		textarea.setAttribute("readonly", "readonly")
		textarea.style.position = "absolute"
		textarea.style.left = "-9999px"
		document.body.appendChild(textarea)
		textarea.select()
		document.execCommand("copy")
		document.body.removeChild(textarea)
	}

	const copyText = async (text) => {
		if (navigator.clipboard?.writeText) {
			await navigator.clipboard.writeText(text)
			return
		}

		fallbackCopy(text)
	}

	const updateLabel = (link) => {
		const label = link.querySelector("span.flex-1") || link
		const originalLabel = label.textContent.trim() || "Copy URL"
		label.textContent = "Copied!"
		window.setTimeout(() => {
			label.textContent = originalLabel
		}, 5000)
	}

	document.addEventListener("click", async (event) => {
		const link = event.target.closest("a[href*='#copy-url=']")
		if (!link) return

		event.preventDefault()
		event.stopPropagation()
		event.stopImmediatePropagation()

		const url = new URL(link.href, window.location.origin)
		const hash = url.hash || ""
		if (!hash.startsWith("#copy-url=")) return

		const copyValue = decodeURIComponent(hash.slice("#copy-url=".length))
		if (!copyValue) return

		try {
			await copyText(copyValue)
			updateLabel(link)
		} catch (_error) {
			// Keep behavior silent when clipboard APIs are unavailable or blocked.
		}
	}, true)
}

