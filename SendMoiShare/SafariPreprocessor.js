var SendMoiSafariPreprocessor = function() {};

SendMoiSafariPreprocessor.prototype = {
    run: function(arguments) {
        var url = document.location ? document.location.href : "";
        var host = document.location && document.location.host ? document.location.host.toLowerCase() : "";
        var selectedText = this.normalizedText(window.getSelection ? window.getSelection().toString() : "");
        var excerpt = selectedText || this.extractExcerpt(host);

        arguments.completionFunction({
            title: document.title || "",
            url: url,
            excerpt: excerpt,
            selectedText: selectedText
        });
    },

    extractExcerpt: function(host) {
        if (host === "x.com" || host === "www.x.com" || host === "twitter.com" || host === "www.twitter.com") {
            var tweetText = this.extractXTweetText();
            if (tweetText) {
                return tweetText;
            }
        }

        return this.metaContent("twitter:description")
            || this.metaContent("og:description")
            || this.metaContent("description");
    },

    extractXTweetText: function() {
        var candidates = document.querySelectorAll('article [data-testid="tweetText"]');
        for (var i = 0; i < candidates.length; i += 1) {
            var text = this.normalizedText(candidates[i].innerText || candidates[i].textContent || "");
            if (text) {
                return text;
            }
        }

        return "";
    },

    metaContent: function(name) {
        var selectors = [
            'meta[name="' + name + '"]',
            'meta[property="' + name + '"]'
        ];

        for (var i = 0; i < selectors.length; i += 1) {
            var node = document.querySelector(selectors[i]);
            var content = node ? this.normalizedText(node.getAttribute("content") || "") : "";
            if (content) {
                return content;
            }
        }

        return "";
    },

    normalizedText: function(value) {
        return (value || "")
            .replace(/\s+/g, " ")
            .trim();
    }
};

var ExtensionPreprocessingJS = new SendMoiSafariPreprocessor();
