using Sitecore.DataExchange.Models;

namespace Feature.DataExchange.Providers.FileSystem
{
    public static class SitecoreDeleteItemEndpointExtensions
    {
        public static SitecoreDeleteItemSettings GetSitecoreDeleteItemSettings(this PipelineStep pipelineStep)
        {
            return pipelineStep.GetPlugin<SitecoreDeleteItemSettings>();
        }
        public static bool HasSitecoreDeleteItemSettings(this PipelineStep pipelineStep)
        {
            return (GetSitecoreDeleteItemSettings(pipelineStep) != null);
        }
    }
}
