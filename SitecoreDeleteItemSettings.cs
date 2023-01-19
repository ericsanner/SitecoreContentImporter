using Sitecore.Data.Items;
using Sitecore.DataExchange;
using Sitecore.DataExchange.Providers.Sc.Converters.DataAccess.ValueAccessors;
using Sitecore.Services.Core.Model;

namespace Feature.DataExchange.Providers.FileSystem
{
    public class SitecoreDeleteItemSettings : IPlugin
    {
        public SitecoreDeleteItemSettings() { }             
        public ItemModel Field { get; set; }
        public string Matches { get; set; }
    }
}
