var SendMoiSafariPreprocessor = function() {};

SendMoiSafariPreprocessor.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            title: document.title || "",
            url: document.location ? document.location.href : ""
        });
    }
};

var ExtensionPreprocessingJS = new SendMoiSafariPreprocessor();
