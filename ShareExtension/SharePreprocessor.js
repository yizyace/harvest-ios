// Apple JS preprocessor: runs in the page Safari is sharing, hands the
// post-render DOM back to the extension. Results land as a [String: Any]
// dict under NSExtensionJavaScriptPreprocessingResultsKey on the share
// extension's NSItemProvider for kUTTypePropertyList.
class HarvestPreprocessor {
    run(args) {
        args.completionFunction({
            url: document.URL,
            title: document.title,
            html: document.documentElement.outerHTML
        });
    }

    finalize() {}
}

var ExtensionPreprocessingJS = new HarvestPreprocessor();
