;(function($) {
    $.fn.textfill = function(options) {
        var fontSize = options.maxFontPixels;
        var ourText = $('span:visible:first', this);
        var maxHeight = $(this).height();
        var maxWidth = options.maxWidth || $(this).width();
        var textHeight;
        var textWidth;
		// TODO: binary search
        do {
            ourText.css({
				'font-size': fontSize,
				'line-height': fontSize + 'px'
			});
            textHeight = ourText.height();
            textWidth = ourText.width();
            fontSize = fontSize - 1;
        } while ((textWidth > maxWidth) && fontSize > 3);
        return this;
    }
})(jQuery);

